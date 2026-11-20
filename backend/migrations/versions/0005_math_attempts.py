"""Maths attempts, the basis for strengths and weaknesses per topic."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0005_math_attempts"
down_revision = "0004_tests_push_plans"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "math_attempts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("level", sa.String(length=16), nullable=False),
        sa.Column("topic", sa.String(length=64), nullable=False),
        sa.Column("difficulty", sa.Integer(), nullable=False),
        sa.Column("score", sa.Float(), nullable=False),
        sa.Column("mistake_skill", sa.String(length=120), nullable=False, server_default=""),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_math_attempts_account_topic", "math_attempts", ["account_id", "topic", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_math_attempts_account_topic", table_name="math_attempts")
    op.drop_table("math_attempts")
