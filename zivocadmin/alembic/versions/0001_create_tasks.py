"""create tasks

Revision ID: 0001
Revises:
Create Date: 2026-10-13
"""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    if "tasks" in sa.inspect(bind).get_table_names():
        return
    op.create_table(
        "tasks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("assignee", sa.Text(), nullable=False),
        sa.Column("assignee_name", sa.Text(), nullable=False),
        sa.Column("assignee_role", sa.Text(), nullable=False),
        sa.Column("created_by", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("tasks_assignee_idx", "tasks", [sa.text("lower(assignee)")])


def downgrade():
    op.drop_index("tasks_assignee_idx", table_name="tasks")
    op.drop_table("tasks")
