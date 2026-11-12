"""ASGI middleware: request body size limit and security response headers."""

from __future__ import annotations

import json

SECURITY_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"referrer-policy", b"strict-origin-when-cross-origin"),
    (b"x-frame-options", b"DENY"),
    (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
    (b"content-security-policy", b"default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"),
]
HSTS_HEADER = (b"strict-transport-security", b"max-age=31536000; includeSubDomains")


class BodyLimitAndSecurityHeadersMiddleware:
    def __init__(self, application, max_bytes: int):
        self.application = application
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.application(scope, receive, send)
            return
        headers = {key.lower(): value for key, value in scope.get("headers", [])}
        forwarded_proto = headers.get(b"x-forwarded-proto", b"").split(b",", 1)[0].strip()
        is_https = forwarded_proto == b"https" or scope.get("scheme") == "https"

        async def send_with_security_headers(message):
            if message["type"] == "http.response.start":
                response_headers = list(message.get("headers", [])) + SECURITY_HEADERS
                if is_https:
                    response_headers.append(HSTS_HEADER)
                message = {**message, "headers": response_headers}
            await send(message)

        raw_length = headers.get(b"content-length")
        if raw_length is not None:
            try:
                declared = int(raw_length)
            except ValueError:
                await self._reject(send_with_security_headers, 400, "Invalid content length")
                return
            if declared > self.max_bytes:
                await self._reject(send_with_security_headers, 413, "Request body is too large")
                return
            # The server enforces the declared length, so the body can stream through unbuffered.
            await self.application(scope, receive, send_with_security_headers)
            return

        # No declared length (chunked upload): buffer so an oversized body is rejected cleanly.
        chunks: list[bytes] = []
        size = 0
        more_body = True
        while more_body:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > self.max_bytes:
                await self._reject(send_with_security_headers, 413, "Request body is too large")
                return
            chunks.append(chunk)
            more_body = message.get("more_body", False)
        body = b"".join(chunks)
        consumed = False

        async def replay_body():
            nonlocal consumed
            if not consumed:
                consumed = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        await self.application(scope, replay_body, send_with_security_headers)

    async def _reject(self, send, response_status: int, message: str):
        body = json.dumps({"detail": message}).encode("utf-8")
        await send({"type": "http.response.start", "status": response_status, "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]})
        await send({"type": "http.response.body", "body": body})
