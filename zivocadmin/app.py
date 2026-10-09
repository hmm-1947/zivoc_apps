import base64
import hashlib
import json
import os
import secrets
from functools import wraps
from urllib.parse import urlencode

import psycopg2
import requests
from flask import Flask, jsonify, redirect, render_template, request, session, url_for

from config import Config
from db import create_task, init_db, tasks_for

app = Flask(__name__)
app.config.from_object(Config)


def current_user():
    return session.get("user")


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not current_user():
            return redirect(url_for("index"))
        return view(*args, **kwargs)

    return wrapped


def frappe_request(method, path, **kwargs):
    headers = kwargs.pop("headers", {})
    if Config.FRAPPE_SITE_NAME:
        headers["X-Frappe-Site-Name"] = Config.FRAPPE_SITE_NAME
    return requests.request(
        method,
        Config.FRAPPE_INTERNAL_URL + path,
        headers=headers,
        timeout=15,
        **kwargs,
    )


def pkce_pair():
    verifier = secrets.token_urlsafe(64)
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return verifier, challenge


def redirect_uri():
    return Config.APP_URL + url_for("auth_callback")


def render_error(message, status=400):
    return render_template("error.html", message=message), status


@app.get("/")
def index():
    return render_template("index.html", user=current_user())


@app.get("/login")
def login():
    if current_user():
        return redirect(url_for("index"))
    if not Config.OAUTH_CLIENT_ID:
        return render_error("Zivoc sign-in is not configured on this server.", 500)

    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(16)
    session["oauth"] = {"state": state, "verifier": verifier, "nonce": nonce}

    params = {
        "client_id": Config.OAUTH_CLIENT_ID,
        "response_type": "code",
        "scope": Config.OAUTH_SCOPE,
        "redirect_uri": redirect_uri(),
        "state": state,
        "nonce": nonce,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    return redirect(Config.FRAPPE_URL + Config.AUTHORIZE_PATH + "?" + urlencode(params))


@app.get("/auth/callback")
def auth_callback():
    saved = session.pop("oauth", None)
    if not saved:
        return render_error("Your sign-in session expired. Please try again.")

    if request.args.get("error"):
        return render_error("Zivoc sign-in was cancelled or denied.", 403)

    code = request.args.get("code")
    state = request.args.get("state")
    if not code or not state or not secrets.compare_digest(state, saved["state"]):
        return render_error("Invalid sign-in response. Please try again.")

    try:
        token_response = frappe_request(
            "POST",
            Config.TOKEN_PATH,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect_uri(),
                "client_id": Config.OAUTH_CLIENT_ID,
                "client_secret": Config.OAUTH_CLIENT_SECRET,
                "code_verifier": saved["verifier"],
            },
        )
        if token_response.status_code != 200:
            return render_error("Zivoc rejected the sign-in request.", 401)
        access_token = token_response.json().get("access_token")
        if not access_token:
            return render_error("Zivoc did not return an access token.", 401)

        profile_response = frappe_request(
            "GET",
            Config.USERINFO_PATH,
            headers={"Authorization": "Bearer " + access_token},
        )
        if profile_response.status_code != 200:
            return render_error("Could not read your Zivoc profile.", 401)
        profile = profile_response.json()
    except (requests.RequestException, ValueError):
        return render_error("Could not reach the Zivoc server. Please try again.", 502)

    email = (profile.get("email") or "").strip().lower()
    if not email:
        return render_error("Your Zivoc account has no email address.", 403)

    session.clear()
    session.permanent = True
    session["user"] = {
        "email": email,
        "name": profile.get("name") or email,
        "picture": profile.get("picture"),
        "roles": profile.get("roles") or [],
    }
    session["token"] = access_token
    return redirect(url_for("index"))


@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


@app.get("/erp")
@login_required
def erp():
    return redirect(Config.FRAPPE_URL + Config.ERP_PATH)

def fetch_people():
    token = session.get("token")
    if not token:
        return None
    people = {}
    for role in Config.TASK_ROLES:
        response = frappe_request(
            "GET",
            "/api/resource/User",
            headers={"Authorization": "Bearer " + token},
            params={
                "filters": json.dumps(
                    [
                        ["Has Role", "role", "=", role],
                        ["enabled", "=", 1],
                        ["name", "not in", ["Administrator", "Guest"]],
                    ]
                ),
                "fields": json.dumps(["name", "full_name", "user_image"]),
                "order_by": "full_name asc",
                "limit_page_length": 0,
            },
        )
        response.raise_for_status()
        people[role] = response.json().get("data", [])
    return people


def erp_identity(sid):
    headers = {"Cookie": "sid=" + sid}
    who = frappe_request("GET", "/api/method/frappe.auth.get_logged_user", headers=dict(headers))
    if who.status_code != 200:
        return None, []
    name = who.json().get("message")
    roles = frappe_request(
        "GET", "/api/method/frappe.core.doctype.user.user.get_roles", headers=dict(headers)
    )
    if roles.status_code != 200:
        return None, []
    return name, roles.json().get("message") or []


@app.get("/tasks")
@login_required
def tasks_page():
    people, error = None, None
    try:
        people = fetch_people()
        if people is None:
            error = "Your session has no ERP access. Please sign out and sign in again."
    except (requests.RequestException, ValueError):
        error = "Could not load people from Zivoc ERP."
    return render_template(
        "tasks.html",
        user=current_user(),
        people=people or {},
        error=error,
        sent=request.args.get("sent"),
    )


@app.route("/tasks/assign", methods=["GET", "POST"])
@login_required
def assign_task():
    email = (request.values.get("user") or "").strip()
    role = (request.values.get("role") or "").strip()
    try:
        people = fetch_people() or {}
    except (requests.RequestException, ValueError):
        return render_error("Could not load people from Zivoc ERP.", 502)

    person = next((p for p in people.get(role, []) if p["name"] == email), None)
    if not person:
        return redirect(url_for("tasks_page"))
    person_name = person.get("full_name") or person["name"]

    error = None
    title = ""
    description = ""
    if request.method == "POST":
        title = (request.form.get("title") or "").strip()
        description = (request.form.get("description") or "").strip()
        if not title:
            error = "Task name is required."
        else:
            try:
                create_task(title, description, person["name"], person_name, role, current_user()["email"])
            except psycopg2.Error:
                error = "Could not save the task. Please try again."
            else:
                return redirect(url_for("tasks_page", sent=person_name))

    return render_template(
        "assign_task.html",
        user=current_user(),
        person=person,
        person_name=person_name,
        role=role,
        title=title,
        description=description,
        error=error,
    )


@app.get("/api/tasks")
def api_tasks():
    sid = (request.headers.get("X-ERP-SID") or "").strip()
    if not sid:
        return jsonify({"message": "Missing session."}), 401
    try:
        name, roles = erp_identity(sid)
    except (requests.RequestException, ValueError):
        return jsonify({"message": "Could not reach Zivoc ERP."}), 502
    if not name:
        return jsonify({"message": "Invalid session."}), 401
    if not set(roles) & set(Config.TASK_ROLES):
        return jsonify({"message": "Only fabricators and salesmen can view tasks."}), 403
    rows = tasks_for(name)
    return jsonify(
        {
            "tasks": [
                {
                    "id": r["id"],
                    "title": r["title"],
                    "description": r["description"],
                    "created_at": r["created_at"].isoformat(),
                }
                for r in rows
            ]
        }
    )


init_db()

if __name__ == "__main__":
    app.run(host=os.environ.get("APP_HOST", "127.0.0.1"), port=5000, debug=True)
