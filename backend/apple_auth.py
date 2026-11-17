"""Sign in with Apple: identity-token verification and token revocation."""

from __future__ import annotations

import hashlib
import json
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

import jwt
from fastapi import HTTPException

import config

APPLE_ISSUER = "https://appleid.apple.com"
JWKS_URL = APPLE_ISSUER + "/auth/keys"
TOKEN_URL = APPLE_ISSUER + "/auth/token"
REVOKE_URL = APPLE_ISSUER + "/auth/revoke"
JWKS_TTL_SECONDS = 3600
# An unknown key id triggers a re-fetch, but not more often than this: tokens with made-up ids must not turn into requests to Apple.
JWKS_MIN_REFETCH_SECONDS = 60

_jwks: dict[str, Any] = {}
_jwks_loaded_at = 0.0
_jwks_lock = threading.Lock()


def _invalid() -> HTTPException:
    return HTTPException(status_code=401, detail="Apple sign-in could not be verified")


def apple_public_keys(force: bool = False) -> dict[str, Any]:
    """Apple's signing keys by key id, cached for an hour."""
    global _jwks, _jwks_loaded_at
    with _jwks_lock:
        age = time.time() - _jwks_loaded_at
        if not _jwks or age > JWKS_TTL_SECONDS or (force and age > JWKS_MIN_REFETCH_SECONDS):
            try:
                with urllib.request.urlopen(JWKS_URL, timeout=10) as response:
                    payload = json.loads(response.read())
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
                raise HTTPException(status_code=503, detail="Apple sign-in is temporarily unavailable")
            _jwks = {key["kid"]: key for key in payload.get("keys", []) if isinstance(key, dict) and "kid" in key}
            _jwks_loaded_at = time.time()
        return _jwks


def verify_identity_token(identity_token: str, raw_nonce: str) -> dict[str, Any]:
    """Validate an Apple identity token issued for this app and bound to the given nonce."""
    try:
        key_id = jwt.get_unverified_header(identity_token).get("kid", "")
    except jwt.PyJWTError:
        raise _invalid()
    keys = apple_public_keys()
    if key_id not in keys:
        keys = apple_public_keys(force=True)
    if key_id not in keys:
        raise _invalid()
    try:
        public_key = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(keys[key_id]))
        claims = jwt.decode(identity_token, public_key, algorithms=["RS256"], audience=config.APPLE_BUNDLE_ID, issuer=APPLE_ISSUER)
    except (jwt.PyJWTError, ValueError, KeyError):
        raise _invalid()
    # The app sends the SHA-256 of its random nonce to Apple; a replayed token carries a different one.
    if claims.get("nonce") != hashlib.sha256(raw_nonce.encode()).hexdigest():
        raise _invalid()
    if not str(claims.get("sub", "")).strip():
        raise _invalid()
    return claims


def verified_email(claims: dict[str, Any]) -> Optional[str]:
    """The email Apple vouches for, lower-cased; None when absent or unverified."""
    email = str(claims.get("email") or "").strip().lower()
    verified = claims.get("email_verified")
    if not email or verified not in (True, "true"):
        return None
    return email[:320]


def revocation_configured() -> bool:
    return bool(config.APPLE_TEAM_ID and config.APPLE_KEY_ID and config.APPLE_PRIVATE_KEY)


def _client_secret() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": config.APPLE_TEAM_ID, "iat": now, "exp": now + 300, "aud": APPLE_ISSUER, "sub": config.APPLE_BUNDLE_ID},
        config.APPLE_PRIVATE_KEY, algorithm="ES256", headers={"kid": config.APPLE_KEY_ID},
    )


def _post_form(url: str, fields: dict[str, str]) -> dict[str, Any]:
    request = urllib.request.Request(
        url, data=urllib.parse.urlencode(fields).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        body = response.read()
    return json.loads(body) if body else {}


def refresh_token_for(authorization_code: str) -> Optional[str]:
    """Exchange the one-time code for a refresh token, kept only so the grant can be revoked on deletion."""
    if not revocation_configured() or not authorization_code:
        return None
    try:
        result = _post_form(TOKEN_URL, {
            "client_id": config.APPLE_BUNDLE_ID, "client_secret": _client_secret(),
            "code": authorization_code, "grant_type": "authorization_code",
        })
    except Exception:
        print("Apple code exchange failed.", flush=True)
        return None
    token = result.get("refresh_token")
    return token if isinstance(token, str) and token else None


def revoke(refresh_token: Optional[str]) -> None:
    """Tell Apple the account is gone. Best effort: deletion must not fail because Apple is unreachable."""
    if not revocation_configured() or not refresh_token:
        return
    try:
        _post_form(REVOKE_URL, {
            "client_id": config.APPLE_BUNDLE_ID, "client_secret": _client_secret(),
            "token": refresh_token, "token_type_hint": "refresh_token",
        })
    except Exception:
        print("Apple token revocation failed.", flush=True)
