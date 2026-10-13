from datetime import datetime

from sqlalchemy import DateTime, Index, Text, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, server_default="")
    assignee: Mapped[str] = mapped_column(Text, nullable=False)
    assignee_name: Mapped[str] = mapped_column(Text, nullable=False)
    assignee_role: Mapped[str] = mapped_column(Text, nullable=False)
    created_by: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


Index("tasks_assignee_idx", func.lower(Task.__table__.c.assignee))
