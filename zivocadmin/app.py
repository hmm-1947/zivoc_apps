import base64
import hashlib
import json
import secrets
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode

import requests
import uvicorn
from fastapi import Depends, FastAPI, Form, Header, Query, Request
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from jinja2 import pass_context
from sqlalchemy.exc import SQLAlchemyError
from starlette.middleware.sessions import SessionMiddleware

from config import Config
from db import create_task, delete_task, tasks_for

BASE_DIR = Path(__file__).resolve().parent

app = FastAPI(title="Zivoc Admin")
app.add_middleware(
    SessionMiddleware,
    secret_key=Config.SECRET_KEY,
    session_cookie=Config.SESSION_COOKIE_NAME,
    max_age=Config.SESSION_SECONDS,
    same_site="lax",
    https_only=False,
)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")

templates = Jinja2Templates(directory=BASE_DIR / "templates")


@pass_context
def url_for(context, name, **params):
    app_ = context["request"].app
    if name == "static":
        return str(app_.url_path_for("static", path=params["filename"]))
    path = str(app_.url_path_for(name))
    query = {k: v for k, v in params.items() if v is not None}
    return path + ("?" + urlencode(query) if query else "")


templates.env.globals["url_for"] = url_for


class NotAuthenticated(Exception):
    pass


@app.exception_handler(NotAuthenticated)
def not_authenticated_handler(request: Request, exc: NotAuthenticated):
    return RedirectResponse(url="/", status_code=303)


def current_user(request: Request):
    return request.session.get("user")


def require_user(request: Request):
    user = current_user(request)
    if not user:
        raise NotAuthenticated()
    return user


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


def redirect_uri(request: Request):
    return Config.APP_URL + request.app.url_path_for("auth_callback")


def render(request: Request, name: str, context: dict, status: int = 200):
    return templates.TemplateResponse(request, name, context, status_code=status)


def render_error(request: Request, message: str, status: int = 400):
    return render(request, "error.html", {"message": message}, status)


def refresh_token(request: Request):
    saved = request.session.get("refresh_token")
    if not saved:
        return False
    response = frappe_request(
        "POST",
        Config.TOKEN_PATH,
        data={
            "grant_type": "refresh_token",
            "refresh_token": saved,
            "client_id": Config.OAUTH_CLIENT_ID,
            "client_secret": Config.OAUTH_CLIENT_SECRET,
        },
    )
    if response.status_code != 200:
        return False
    body = response.json()
    if not body.get("access_token"):
        return False
    request.session["token"] = body["access_token"]
    request.session["refresh_token"] = body.get("refresh_token") or saved
    return True


def erp_authed(request: Request, method, path, **kwargs):
    def send():
        headers = dict(kwargs.get("headers") or {})
        headers["Authorization"] = "Bearer " + (request.session.get("token") or "")
        return frappe_request(method, path, **{**kwargs, "headers": headers})

    response = send()
    if response.status_code == 401 and refresh_token(request):
        response = send()
    if response.status_code == 401:
        request.session.clear()
        raise NotAuthenticated()
    return response


def fetch_people(request: Request):
    if not request.session.get("token"):
        return None
    people = {}
    for role in Config.TASK_ROLES:
        response = erp_authed(
            request,
            "GET",
            "/api/method/custom_layer.drawing_auth.get_users_by_role",
            params={"role": role},
        )
        response.raise_for_status()
        people[role] = response.json().get("message", [])
    return people
def erp_identity(sid):
    headers = {"Cookie": "sid=" + sid}
    me = frappe_request(
        "GET", "/api/method/custom_layer.drawing_auth.me", headers=dict(headers)
    )
    if me.status_code != 200:
        return None, []
    name = (me.json().get("message") or {}).get("user")
    if not name:
        return None, []
    roles = frappe_request(
        "GET", "/api/method/custom_layer.drawing_auth.get_roles", headers=dict(headers)
    )
    if roles.status_code != 200:
        return None, []
    return name, roles.json().get("message") or []


@app.get("/")
def index(request: Request):
    return render(request, "index.html", {"user": current_user(request)})


@app.get("/login")
def login(request: Request):
    if current_user(request):
        return RedirectResponse(url="/", status_code=303)
    if not Config.OAUTH_CLIENT_ID:
        return render_error(request, "Zivoc sign-in is not configured on this server.", 500)

    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(16)
    request.session["oauth"] = {"state": state, "verifier": verifier, "nonce": nonce}

    params = {
        "client_id": Config.OAUTH_CLIENT_ID,
        "response_type": "code",
        "scope": Config.OAUTH_SCOPE,
        "redirect_uri": redirect_uri(request),
        "state": state,
        "nonce": nonce,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    return RedirectResponse(
        url=Config.FRAPPE_URL + Config.AUTHORIZE_PATH + "?" + urlencode(params),
        status_code=302,
    )


@app.get("/auth/callback")
def auth_callback(request: Request):
    saved = request.session.pop("oauth", None)
    if not saved:
        return render_error(request, "Your sign-in session expired. Please try again.")

    if request.query_params.get("error"):
        return render_error(request, "Zivoc sign-in was cancelled or denied.", 403)

    code = request.query_params.get("code")
    state = request.query_params.get("state")
    if not code or not state or not secrets.compare_digest(state, saved["state"]):
        return render_error(request, "Invalid sign-in response. Please try again.")

    try:
        token_response = frappe_request(
            "POST",
            Config.TOKEN_PATH,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect_uri(request),
                "client_id": Config.OAUTH_CLIENT_ID,
                "client_secret": Config.OAUTH_CLIENT_SECRET,
                "code_verifier": saved["verifier"],
            },
        )
        if token_response.status_code != 200:
            return render_error(request, "Zivoc rejected the sign-in request.", 401)
        access_token = token_response.json().get("access_token")
        if not access_token:
            return render_error(request, "Zivoc did not return an access token.", 401)

        profile_response = frappe_request(
            "GET",
            Config.USERINFO_PATH,
            headers={"Authorization": "Bearer " + access_token},
        )
        if profile_response.status_code != 200:
            return render_error(request, "Could not read your Zivoc profile.", 401)
        profile = profile_response.json()
    except (requests.RequestException, ValueError):
        return render_error(request, "Could not reach the Zivoc server. Please try again.", 502)

    email = (profile.get("email") or "").strip().lower()
    if not email:
        return render_error(request, "Your Zivoc account has no email address.", 403)

    request.session.clear()
    request.session["user"] = {
        "email": email,
        "name": profile.get("name") or email,
        "picture": profile.get("picture"),
        "roles": profile.get("roles") or [],
    }
    request.session["token"] = access_token
    request.session["refresh_token"] = token_response.json().get("refresh_token")
    return RedirectResponse(url="/", status_code=303)


@app.post("/logout")
def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/", status_code=303)


@app.get("/erp")
def erp(user: dict = Depends(require_user)):
    return RedirectResponse(url=Config.FRAPPE_URL + Config.ERP_PATH, status_code=302)


@app.get("/tasks")
def tasks_page(request: Request, user: dict = Depends(require_user), sent: Optional[str] = None):
    people, error = None, None
    try:
        people = fetch_people(request)
        if people is None:
            error = "Your session has no ERP access. Please sign out and sign in again."
    except (requests.RequestException, ValueError):
        error = "Could not load people from Zivoc ERP."
    return render(
        request,
        "tasks.html",
        {"user": user, "people": people or {}, "error": error, "sent": sent},
    )


def render_assign(request, user, person, role, title, description, error, sent, deleted):
    person_name = person.get("full_name") or person["name"]
    try:
        existing = tasks_for(person["name"])
    except SQLAlchemyError:
        existing = []
        error = error or "Could not load existing tasks."
    return render(
        request,
        "assign_task.html",
        {
            "user": user,
            "person": person,
            "person_name": person_name,
            "role": role,
            "title": title,
            "description": description,
            "error": error,
            "tasks": existing,
            "sent": sent,
            "deleted": deleted,
        },
    )


def find_person(request, email, role):
    people = fetch_people(request) or {}
    return next((p for p in people.get(role, []) if p["name"] == email), None)


@app.get("/tasks/assign", name="assign_task")
def assign_task_page(
    request: Request,
    user: dict = Depends(require_user),
    email: str = Query("", alias="user"),
    role: str = "",
    sent: Optional[str] = None,
    deleted: Optional[str] = None,
):
    try:
        person = find_person(request, email.strip(), role.strip())
    except (requests.RequestException, ValueError):
        return render_error(request, "Could not load people from Zivoc ERP.", 502)
    if not person:
        return RedirectResponse(url=request.app.url_path_for("tasks_page"), status_code=303)
    return render_assign(request, user, person, role.strip(), "", "", None, sent, deleted)


@app.post("/tasks/assign", name="assign_task")
def assign_task_submit(
    request: Request,
    user: dict = Depends(require_user),
    email: str = Form("", alias="user"),
    role: str = Form(""),
    title: str = Form(""),
    description: str = Form(""),
):
    email, role = email.strip(), role.strip()
    try:
        person = find_person(request, email, role)
    except (requests.RequestException, ValueError):
        return render_error(request, "Could not load people from Zivoc ERP.", 502)
    if not person:
        return RedirectResponse(url=request.app.url_path_for("tasks_page"), status_code=303)

    title, description = title.strip(), description.strip()
    error = None
    if not title:
        error = "Task name is required."
    else:
        person_name = person.get("full_name") or person["name"]
        try:
            create_task(title, description, person["name"], person_name, role, user["email"])
        except SQLAlchemyError:
            error = "Could not save the task. Please try again."
        else:
            query = urlencode({"user": person["name"], "role": role, "sent": 1})
            return RedirectResponse(
                url=request.app.url_path_for("assign_task") + "?" + query, status_code=303
            )

    return render_assign(request, user, person, role, title, description, error, None, None)


@app.post("/tasks/delete", name="remove_task")
def remove_task(
    request: Request,
    user: dict = Depends(require_user),
    email: str = Form("", alias="user"),
    role: str = Form(""),
    task_id: str = Form(""),
):
    email, role = email.strip(), role.strip()
    try:
        tid = int(task_id or 0)
    except ValueError:
        tid = 0
    if email and tid:
        try:
            delete_task(tid, email)
        except SQLAlchemyError:
            return render_error(request, "Could not delete the task.", 500)
    query = urlencode({"user": email, "role": role, "deleted": 1})
    return RedirectResponse(
        url=request.app.url_path_for("assign_task") + "?" + query, status_code=303
    )


@app.get("/commission", name="commission_page")
def commission_page(
    request: Request,
    user: dict = Depends(require_user),
    done: Optional[str] = None,
    error: Optional[str] = None,
):
    salesmen = []
    try:
        response = erp_authed(
            request,
            "GET",
            "/api/method/custom_layer.commission.list_salesmen",
        )
        data = erp_message(response)
        if response.status_code == 200 and data.get("ok"):
            salesmen = data.get("salesmen", [])
        else:
            error = error or data.get("message") or "Could not load salesmen from Zivoc ERP."
    except (requests.RequestException, ValueError):
        error = error or "Could not load salesmen from Zivoc ERP."
    return render(
        request,
        "commission.html",
        {"user": user, "salesmen": salesmen, "error": error, "done": done},
    )


@app.post("/commission/set", name="commission_set")
def commission_set(
    request: Request,
    user: dict = Depends(require_user),
    percent: str = Form(""),
    target: str = Form("", alias="user"),
    apply_to_all: str = Form(""),
):
    query = {}
    payload = {"percent": percent.strip(), "apply_to_all": 1 if apply_to_all else 0}
    if target.strip():
        payload["user"] = target.strip()
    try:
        response = erp_authed(
            request,
            "POST",
            "/api/method/custom_layer.commission.set_commission",
            data=payload,
        )
        data = erp_message(response)
        if response.status_code == 200 and data.get("ok"):
            count = data.get("updated", 0)
            query["done"] = "Commission set to %s%% for %s salesm%s." % (
                data.get("percent"),
                count,
                "an" if count == 1 else "en",
            )
        else:
            query["error"] = data.get("message") or "Could not save the commission."
    except (requests.RequestException, ValueError):
        query["error"] = "Could not reach Zivoc ERP."
    return RedirectResponse(
        url=request.app.url_path_for("commission_page") + "?" + urlencode(query), status_code=303
    )

@app.post("/commission/target", name="target_set")
def target_set(
    request: Request,
    user: dict = Depends(require_user),
    amount: str = Form(""),
    target: str = Form("", alias="user"),
    apply_to_all: str = Form(""),
):
    query = {}
    payload = {"amount": amount.strip(), "apply_to_all": 1 if apply_to_all else 0}
    if target.strip():
        payload["user"] = target.strip()
    try:
        response = erp_authed(
            request,
            "POST",
            "/api/method/custom_layer.commission.set_target",
            data=payload,
        )
        data = erp_message(response)
        if response.status_code == 200 and data.get("ok"):
            count = data.get("updated", 0)
            query["done"] = "Monthly target set to %s for %s salesm%s." % (
                formatted_amount(data.get("amount")),
                count,
                "an" if count == 1 else "en",
            )
        else:
            query["error"] = data.get("message") or "Could not save the target."
    except (requests.RequestException, ValueError):
        query["error"] = "Could not reach Zivoc ERP."
    return RedirectResponse(
        url=request.app.url_path_for("commission_page") + "?" + urlencode(query), status_code=303
    )


def formatted_amount(value):
    try:
        return "{:,.2f}".format(float(value))
    except (TypeError, ValueError):
        return str(value)


def erp_message(response):
    try:
        body = response.json()
    except ValueError:
        return {}
    message = body.get("message")
    return message if isinstance(message, dict) else body


@app.get("/orders", name="orders_page")
def orders_page(
    request: Request,
    user: dict = Depends(require_user),
    done: Optional[str] = None,
    error: Optional[str] = None,
):
    orders = []
    try:
        response = erp_authed(
            request,
            "GET",
            "/api/method/custom_layer.orders.list_orders",
        )
        data = erp_message(response)
        if response.status_code == 200 and data.get("ok"):
            orders = data.get("orders", [])
        else:
            error = error or data.get("message") or "Could not load orders from Zivoc ERP."
    except (requests.RequestException, ValueError):
        error = error or "Could not load orders from Zivoc ERP."
    return render(
        request,
        "orders.html",
        {"user": user, "orders": orders, "error": error, "done": done},
    )


@app.post("/orders/status", name="order_status")
def order_status(
    request: Request,
    user: dict = Depends(require_user),
    order: str = Form(""),
    status: str = Form(""),
):
    query = {}
    try:
        response = erp_authed(
            request,
            "POST",
            "/api/method/custom_layer.orders.set_order_status",
            data={"order": order.strip(), "status": status.strip()},
        )
        data = erp_message(response)
        if response.status_code == 200 and data.get("ok"):
            query["done"] = order.strip() + " " + status.strip().lower()
        else:
            query["error"] = data.get("message") or "Could not update the order."
    except (requests.RequestException, ValueError):
        query["error"] = "Could not reach Zivoc ERP."
    return RedirectResponse(
        url=request.app.url_path_for("orders_page") + "?" + urlencode(query), status_code=303
    )

@app.get("/api/tasks")
def api_tasks(x_erp_sid: str = Header("")):
    sid = x_erp_sid.strip()
    if not sid:
        return JSONResponse({"message": "Missing session."}, status_code=401)
    try:
        name, roles = erp_identity(sid)
    except (requests.RequestException, ValueError):
        return JSONResponse({"message": "Could not reach Zivoc ERP."}, status_code=502)
    if not name:
        return JSONResponse({"message": "Invalid session."}, status_code=401)
    if not set(roles) & set(Config.TASK_ROLES):
        return JSONResponse(
            {"message": "Only fabricators and salesmen can view tasks."}, status_code=403
        )
    try:
        rows = tasks_for(name)
    except SQLAlchemyError:
        return JSONResponse({"message": "Could not load tasks."}, status_code=500)
    return JSONResponse(
        {
            "tasks": [
                {
                    "id": r.id,
                    "title": r.title,
                    "description": r.description,
                    "created_at": r.created_at.isoformat(),
                }
                for r in rows
            ]
        },
        headers={"Cache-Control": "no-store"},
    )


if __name__ == "__main__":
    uvicorn.run("app:app", host=Config.APP_HOST, port=Config.APP_PORT, reload=True)
