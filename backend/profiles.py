"""Validation of uploaded profile documents."""

from __future__ import annotations

import json
from typing import Any
from uuid import UUID

from fastapi import HTTPException
from jsonschema import Draft202012Validator

from config import MAX_PROFILE_BYTES, PROFILE_SCHEMA_PATH
from db import utcnow


def profile_validator() -> Draft202012Validator:
    with PROFILE_SCHEMA_PATH.open(encoding="utf-8") as stream:
        schema = json.load(stream)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)


PROFILE_VALIDATOR = profile_validator()


def validate_profile_document(document: dict[str, Any], account_id: UUID) -> dict[str, Any]:
    if len(json.dumps(document, ensure_ascii=False).encode("utf-8")) > MAX_PROFILE_BYTES:
        raise HTTPException(status_code=413, detail="Profile is too large")
    errors = list(PROFILE_VALIDATOR.iter_errors(document))
    if errors:
        error = errors[0]
        location = ".".join(str(part) for part in error.absolute_path) or "profile"
        raise HTTPException(status_code=422, detail=f"Invalid profile at {location}: {error.message[:180]}")
    now = utcnow().replace(microsecond=0).isoformat().replace("+00:00", "Z")
    clean = dict(document)
    clean["profile_id"] = str(account_id)
    clean["updated_at"] = now
    return clean
