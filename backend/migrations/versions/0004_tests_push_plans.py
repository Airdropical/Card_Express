"""Daily tests, push notification devices, and the account plan."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0004_tests_push_plans"
down_revision = "0003_apple_sign_in"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("accounts", sa.Column("plan", sa.String(length=16), nullable=False, server_default="free"))
    op.add_column("accounts", sa.Column("last_test_push_day", sa.String(length=10), nullable=True))
    op.create_table(
        "device_tokens",
        sa.Column("token", sa.String(length=200), primary_key=True),
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("environment", sa.String(length=16), nullable=False, server_default="production"),
        sa.Column("language", sa.String(length=8), nullable=False, server_default="de"),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_device_tokens_account_id", "device_tokens", ["account_id"])
    op.create_table(
        "generated_tests",
        sa.Column("account_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("reference", sa.String(length=64), nullable=False),
        sa.Column("day", sa.String(length=10), nullable=False),
        sa.Column("questions", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("account_id", "kind", "reference", "day"),
    )
    op.create_index("ix_generated_tests_created_at", "generated_tests", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_generated_tests_created_at", table_name="generated_tests")
    op.drop_table("generated_tests")
    op.drop_index("ix_device_tokens_account_id", table_name="device_tokens")
    op.drop_table("device_tokens")
    op.drop_column("accounts", "last_test_push_day")
    op.drop_column("accounts", "plan")
