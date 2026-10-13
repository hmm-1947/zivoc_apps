import os
import secrets

from dotenv import load_dotenv

load_dotenv()


def _url(name, default):
    return os.environ.get(name, default).rstrip("/")


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY") or secrets.token_hex(32)
    SESSION_COOKIE_NAME = "zivoc_admin_session"
    SESSION_SECONDS = int(os.environ.get("SESSION_HOURS", "8")) * 3600

    APP_HOST = os.environ.get("APP_HOST", "127.0.0.1")
    APP_PORT = int(os.environ.get("APP_PORT", "5000"))
    APP_URL = _url("APP_URL", "http://localhost:5000")
    FRAPPE_URL = _url("FRAPPE_URL", "http://erp.localhost:8000")
    FRAPPE_INTERNAL_URL = _url("FRAPPE_INTERNAL_URL", os.environ.get("FRAPPE_URL", "http://erp.localhost:8000"))
    FRAPPE_SITE_NAME = os.environ.get("FRAPPE_SITE_NAME", "")

    OAUTH_CLIENT_ID = os.environ.get("OAUTH_CLIENT_ID", "")
    OAUTH_CLIENT_SECRET = os.environ.get("OAUTH_CLIENT_SECRET", "")
    OAUTH_SCOPE = "openid all"

    AUTHORIZE_PATH = "/api/method/frappe.integrations.oauth2.authorize"
    TOKEN_PATH = "/api/method/frappe.integrations.oauth2.get_token"
    USERINFO_PATH = "/api/method/frappe.integrations.oauth2.openid_profile"
    ERP_PATH = "/app"

    DATABASE_URL = os.environ.get("DATABASE_URL", "")
    TASK_ROLES = [r.strip() for r in os.environ.get("TASK_ROLES", "Fabricator,Sales User").split(",") if r.strip()]
