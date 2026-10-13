from sqlalchemy import create_engine, delete, func, select
from sqlalchemy.orm import sessionmaker

from config import Config
from models import Task

engine = create_engine(Config.DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(engine, expire_on_commit=False)


def create_task(title, description, assignee, assignee_name, assignee_role, created_by):
    with SessionLocal.begin() as session:
        task = Task(
            title=title,
            description=description,
            assignee=assignee,
            assignee_name=assignee_name,
            assignee_role=assignee_role,
            created_by=created_by,
        )
        session.add(task)
        session.flush()
        return task.id


def tasks_for(assignee):
    with SessionLocal() as session:
        stmt = (
            select(Task)
            .where(func.lower(Task.assignee) == func.lower(assignee))
            .order_by(Task.created_at.desc())
        )
        return list(session.scalars(stmt))


def delete_task(task_id, assignee):
    with SessionLocal.begin() as session:
        result = session.execute(
            delete(Task).where(
                Task.id == task_id,
                func.lower(Task.assignee) == func.lower(assignee),
            )
        )
        return result.rowcount
