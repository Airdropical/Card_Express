"""Allow accounts that sign in with Apple instead of a password."""

from alembic import op
import sqlalchemy as sa


revision = "0003_apple_sign_in"
down_revision = "0002_ai_usage"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("accounts", sa.Column("apple_sub", sa.String(length=255), nullable=True))
    op.add_column("accounts", sa.Column("apple_refresh_token", sa.Text(), nullable=True))
    op.create_unique_constraint("uq_accounts_apple_sub", "accounts", ["apple_sub"])
    op.alter_column("accounts", "password_hash", existing_type=sa.Text(), nullable=True)


def downgrade() -> None:
    # The old schema requires a value; "!" is not a valid hash, so these accounts simply cannot log in with a password.
    op.execute("UPDATE accounts SET password_hash = '!' WHERE password_hash IS NULL")
    op.alter_column("accounts", "password_hash", existing_type=sa.Text(), nullable=False)
    op.drop_constraint("uq_accounts_apple_sub", "accounts", type_="unique")
    op.drop_column("accounts", "apple_refresh_token")
    op.drop_column("accounts", "apple_sub")
