"""Validation of the learning-data snapshot an account syncs between devices."""

from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException
from jsonschema import Draft202012Validator

from config import MAX_PROFILE_BYTES, SNAPSHOT_SCHEMA_PATH


def _validator() -> Draft202012Validator:
    with SNAPSHOT_SCHEMA_PATH.open(encoding="utf-8") as stream:
        schema = json.load(stream)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


SNAPSHOT_VALIDATOR = _validator()


def validate_snapshot(document: dict[str, Any]) -> dict[str, Any]:
    """Reject snapshots that are too large or not shaped like the app's data; return the document unchanged."""
    if len(json.dumps(document, ensure_ascii=False).encode("utf-8")) > MAX_PROFILE_BYTES:
        raise HTTPException(status_code=413, detail="Learning data is too large to sync")
    error = next(iter(SNAPSHOT_VALIDATOR.iter_errors(document)), None)
    if error is not None:
        location = ".".join(str(part) for part in error.absolute_path) or "snapshot"
        raise HTTPException(status_code=422, detail=f"Invalid learning data at {location}: {error.message[:180]}")
    return document
