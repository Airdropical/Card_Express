"""Apple Push Notification service: sending the daily test notification."""

from __future__ import annotations

import threading
import time
from typing import Any, Optional

import jwt

import config

PRODUCTION_HOST = "https://api.push.apple.com"
SANDBOX_HOST = "https://api.sandbox.push.apple.com"
TOKEN_LIFETIME_SECONDS = 45 * 60

_token: Optional[str] = None
_token_issued_at = 0.0
_token_lock = threading.Lock()


def configured() -> bool:
    return bool(config.APPLE_TEAM_ID and config.APNS_KEY_ID and config.APNS_PRIVATE_KEY)


def _provider_token() -> str:
    """Apple accepts a provider token for up to an hour and throttles frequent re-issuing."""
    global _token, _token_issued_at
    with _token_lock:
        if _token is None or time.time() - _token_issued_at > TOKEN_LIFETIME_SECONDS:
            _token_issued_at = time.time()
            _token = jwt.encode({"iss": config.APPLE_TEAM_ID, "iat": int(_token_issued_at)}, config.APNS_PRIVATE_KEY, algorithm="ES256", headers={"kid": config.APNS_KEY_ID})
        return _token


def payload(title: str, body: str, kind: str) -> dict[str, Any]:
    return {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}, "kind": kind}


def send(client: Any, device_token: str, environment: str, title: str, body: str, kind: str) -> int:
    """Send one notification over the given HTTP/2 client and return Apple's status code (410: token is gone)."""
    host = SANDBOX_HOST if environment == "sandbox" else PRODUCTION_HOST
    response = client.post(
        f"{host}/3/device/{device_token}", json=payload(title, body, kind),
        headers={"authorization": f"bearer {_provider_token()}", "apns-topic": config.APPLE_BUNDLE_ID, "apns-push-type": "alert", "apns-priority": "5"},
    )
    return response.status_code


def open_client() -> Any:
    import httpx  # Imported here so the service starts without it when push is not configured.

    return httpx.Client(http2=True, timeout=10)
