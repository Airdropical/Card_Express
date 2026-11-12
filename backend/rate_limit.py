"""Fixed-window rate limiting backed by PostgreSQL."""

from __future__ import annotations

import hashlib
import random
import time

from fastapi import HTTPException, Request
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from config import CLIENT_IP_HEADER
from db import RateLimitBucket

# Expired windows are removed on roughly one in this many calls instead of on every request.
CLEANUP_EVERY = 50


def client_ip(request: Request) -> str:
    """Client address as reported by the hosting proxy.

    X-Forwarded-For is not used: its leftmost entry is whatever the client sent.
    """
    if CLIENT_IP_HEADER:
        value = request.headers.get(CLIENT_IP_HEADER, "").strip()
        if value:
            return value[:64]
    return request.client.host if request.client else "unknown"


def fail_rate_limit(
    db: Session,
    request: Request,
    bucket: str,
    limit: int,
    window_seconds: int,
    subject: str = "",
    by_ip: bool = True,
) -> None:
    ip = client_ip(request) if by_ip else ""
    identity = hashlib.sha256(f"{bucket}:{ip}:{subject.casefold()}".encode()).hexdigest()
    timestamp = int(time.time())
    current_window = timestamp - timestamp % window_seconds
    statement = (
        insert(RateLimitBucket)
        .values(bucket_key=identity, window_start=current_window, hits=1)
        .on_conflict_do_update(
            index_elements=[RateLimitBucket.bucket_key, RateLimitBucket.window_start],
            set_={"hits": RateLimitBucket.hits + 1},
        )
        .returning(RateLimitBucket.hits)
    )
    hits = db.execute(statement).scalar_one()
    if random.randrange(CLEANUP_EVERY) == 0:
        db.execute(
            text("DELETE FROM rate_limit_buckets WHERE window_start < :oldest"),
            {"oldest": timestamp - 86_400},
        )
    db.commit()
    if hits > limit:
        retry = window_seconds - (int(time.time()) % window_seconds)
        raise HTTPException(status_code=429, detail="Too many requests", headers={"Retry-After": str(retry)})
