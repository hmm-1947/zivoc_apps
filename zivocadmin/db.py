import psycopg2
import psycopg2.extras

from config import Config

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    assignee TEXT NOT NULL,
    assignee_name TEXT NOT NULL,
    assignee_role TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tasks_assignee_idx ON tasks (lower(assignee));
"""


def connect():
    return psycopg2.connect(Config.DATABASE_URL, cursor_factory=psycopg2.extras.RealDictCursor)


def init_db():
    conn = connect()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(SCHEMA)
    finally:
        conn.close()


def create_task(title, description, assignee, assignee_name, assignee_role, created_by):
    conn = connect()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO tasks (title, description, assignee, assignee_name, assignee_role, created_by) "
                "VALUES (%s, %s, %s, %s, %s, %s) RETURNING id",
                (title, description, assignee, assignee_name, assignee_role, created_by),
            )
            return cur.fetchone()["id"]
    finally:
        conn.close()


def tasks_for(assignee):
    conn = connect()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                "SELECT id, title, description, created_at FROM tasks "
                "WHERE lower(assignee) = lower(%s) ORDER BY created_at DESC",
                (assignee,),
            )
            return cur.fetchall()
    finally:
        conn.close()
