"""Password hashing, session tokens, and the authenticated-account dependency."""

from __future__ import annotations

import secrets
import threading
from typing import Optional
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from config import JWT_AUDIENCE, JWT_ISSUER, JWT_SECRET, TOKEN_TTL
from db import Account, get_db, utcnow

PASSWORD_HASHER = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)
PASSWORD_HASH_SLOTS = threading.BoundedSemaphore(3)


def issue_token(account: Account) -> str:
    now = utcnow()
    return jwt.encode(
        {
            "sub": str(account.id),
            "ver": account.token_version,
            "iat": now,
            "exp": now + TOKEN_TTL,
            "iss": JWT_ISSUER,
            "aud": JWT_AUDIENCE,
        },
        JWT_SECRET,
        algorithm="HS256",
    )


def current_account(
    authorization: Optional[str] = Header(default=None), db: Session = Depends(get_db)
) -> Account:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required", headers={"WWW-Authenticate": "Bearer"})
    token = authorization[7:].strip()
    try:
        claims = jwt.decode(token, JWT_SECRET, algorithms=["HS256"], issuer=JWT_ISSUER, audience=JWT_AUDIENCE)
        account_id = UUID(claims["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Invalid or expired session", headers={"WWW-Authenticate": "Bearer"})
    account = db.get(Account, account_id)
    if account is None or claims.get("ver") != account.token_version:
        raise HTTPException(status_code=401, detail="Invalid or expired session", headers={"WWW-Authenticate": "Bearer"})
    return account


def verify_password(password: str, encoded: str) -> bool:
    with PASSWORD_HASH_SLOTS:
        try:
            return PASSWORD_HASHER.verify(encoded, password)
        except (VerifyMismatchError, InvalidHashError):
            return False


def hash_password(password: str) -> str:
    with PASSWORD_HASH_SLOTS:
        return PASSWORD_HASHER.hash(password)


DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(32))
