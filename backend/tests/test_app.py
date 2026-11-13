import asyncio

import pytest
from fastapi import HTTPException
from starlette.requests import Request

import auth
import config
import rate_limit
import server
from middleware import BodyLimitAndSecurityHeadersMiddleware


def request_with(headers, peer="10.0.0.1"):
    raw = [(key.lower().encode(), value.encode()) for key, value in headers.items()]
    return Request({"type": "http", "headers": raw, "client": (peer, 1234)})


def test_client_ip_ignores_forwarded_for(monkeypatch):
    monkeypatch.setattr(rate_limit, "CLIENT_IP_HEADER", "x-real-ip")
    request = request_with({"X-Forwarded-For": "6.6.6.6, 7.7.7.7", "X-Real-IP": "1.2.3.4"})
    assert rate_limit.client_ip(request) == "1.2.3.4"
    assert rate_limit.client_ip(request_with({"X-Forwarded-For": "6.6.6.6"})) == "10.0.0.1"


def test_client_ip_header_can_be_disabled(monkeypatch):
    monkeypatch.setattr(rate_limit, "CLIENT_IP_HEADER", "")
    assert rate_limit.client_ip(request_with({"X-Real-IP": "1.2.3.4"})) == "10.0.0.1"


def test_startup_checks_do_not_depend_on_app_env(monkeypatch):
    monkeypatch.setattr(config, "APP_ENV", "development")
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql+psycopg://u:p@localhost/db")
    assert config.startup_problems() == []
    monkeypatch.setattr(config, "JWT_SECRET", "short")
    assert any("JWT_SECRET" in problem for problem in config.startup_problems())
    monkeypatch.setattr(config, "JWT_SECRET", "x" * 32)
    monkeypatch.setattr(config, "DATABASE_URL", "")
    assert any("DATABASE_URL" in problem for problem in config.startup_problems())


def test_invite_code_is_required_in_production(monkeypatch):
    monkeypatch.setattr(config, "DATABASE_URL", "postgresql+psycopg://u:p@localhost/db")
    monkeypatch.setattr(config, "REGISTRATION_INVITE_CODE", "")
    monkeypatch.setattr(config, "APP_ENV", "production")
    assert any("REGISTRATION_INVITE_CODE" in problem for problem in config.startup_problems())
    monkeypatch.setattr(config, "APP_ENV", "development")
    assert config.startup_problems() == []


def test_password_hash_roundtrip():
    encoded = auth.hash_password("correct horse battery")
    assert auth.verify_password("correct horse battery", encoded)
    assert not auth.verify_password("wrong password", encoded)
    assert not auth.verify_password("anything", "not-a-hash")


class FakeAccount:
    def __init__(self, token_version=0):
        self.id = "7f3c1c1e-5f0a-4c69-9d5e-0d7c3c4e8a11"
        self.token_version = token_version


class FakeDb:
    def __init__(self, account):
        self.account = account

    def get(self, model, key):
        return self.account if self.account and str(key) == self.account.id else None


def test_token_roundtrip_and_revocation():
    account = FakeAccount()
    token = auth.issue_token(account)
    assert auth.current_account("Bearer " + token, FakeDb(account)) is account
    account.token_version += 1
    with pytest.raises(HTTPException) as error:
        auth.current_account("Bearer " + token, FakeDb(account))
    assert error.value.status_code == 401


@pytest.mark.parametrize("header", [None, "", "Basic abc", "Bearer not-a-token"])
def test_missing_or_invalid_token_is_rejected(header):
    with pytest.raises(HTTPException) as error:
        auth.current_account(header, FakeDb(FakeAccount()))
    assert error.value.status_code == 401


def test_ai_and_profile_routes_require_authentication():
    protected = {"/api/generate-cards", "/api/evaluate", "/api/tutor", "/api/agent-plan", "/api/summary", "/api/v1/profile", "/api/v1/account", "/api/v1/auth/logout"}
    seen = set()
    for route in server.app.routes:
        if getattr(route, "path", None) in protected:
            calls = {dependency.call for dependency in route.dependant.dependencies}
            assert auth.current_account in calls, route.path
            seen.add(route.path)
    assert seen == protected


def run_middleware(headers, chunks, max_bytes=10):
    received = {}

    async def application(scope, receive, send):
        body = b""
        while True:
            message = await receive()
            body += message.get("body", b"")
            if not message.get("more_body"):
                break
        received["body"] = body
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    sent = []
    pending = [{"type": "http.request", "body": chunk, "more_body": index < len(chunks) - 1} for index, chunk in enumerate(chunks)]

    async def receive():
        return pending.pop(0)

    async def send(message):
        sent.append(message)

    scope = {"type": "http", "scheme": "http", "headers": headers}
    asyncio.run(BodyLimitAndSecurityHeadersMiddleware(application, max_bytes)(scope, receive, send))
    return sent, received.get("body")


def test_body_within_limit_passes_and_gets_security_headers():
    sent, body = run_middleware([(b"content-length", b"5"), (b"x-forwarded-proto", b"https")], [b"hello"])
    assert body == b"hello" and sent[0]["status"] == 200
    names = {name for name, _ in sent[0]["headers"]}
    assert {b"x-content-type-options", b"content-security-policy", b"strict-transport-security"} <= names


def test_declared_oversized_body_is_rejected_before_reading():
    sent, body = run_middleware([(b"content-length", b"11")], [b"x" * 11])
    assert sent[0]["status"] == 413 and body is None


def test_chunked_oversized_body_is_rejected():
    sent, body = run_middleware([], [b"x" * 6, b"x" * 6])
    assert sent[0]["status"] == 413 and body is None


def test_chunked_body_within_limit_is_replayed():
    sent, body = run_middleware([], [b"abc", b"def"])
    assert sent[0]["status"] == 200 and body == b"abcdef"


def test_invalid_content_length_is_rejected():
    sent, _ = run_middleware([(b"content-length", b"abc")], [b""])
    assert sent[0]["status"] == 400


def test_app_starts_and_serves_public_routes(monkeypatch):
    from starlette.testclient import TestClient

    monkeypatch.setattr(config, "DATABASE_URL", "postgresql+psycopg://u:p@localhost/db")
    with TestClient(server.app) as client:
        for path in ("/", "/privacy", "/api/v1/content"):
            response = client.get(path)
            assert response.status_code == 200, path
            assert response.headers["x-frame-options"] == "DENY"
        # No database is configured in the tests.
        assert client.get("/api/health").status_code == 503
        server.app.dependency_overrides[server.get_db] = lambda: None
        try:
            assert client.post("/api/agent-plan", json={"message": "hi"}).status_code == 401
            assert client.post("/api/v1/auth/login", json={"email": "a@example.com", "password": "x", "extra": 1}).status_code == 422
        finally:
            server.app.dependency_overrides.clear()


def test_app_refuses_to_start_with_invalid_configuration(monkeypatch):
    from starlette.testclient import TestClient

    monkeypatch.setattr(config, "DATABASE_URL", "")
    with pytest.raises(RuntimeError, match="DATABASE_URL"):
        with TestClient(server.app):
            pass


def test_attachment_parts_are_empty_without_material():
    from schemas import TutorRequest

    assert server.attachment_parts(TutorRequest(message="hi")) == []
    assert server.attachment_parts(TutorRequest(message="hi", documentText="   ")) == []


def test_attachment_parts_carry_document_and_image():
    import base64

    from schemas import AgentPlanRequest

    image = base64.b64encode(b"not really a jpeg").decode()
    body = AgentPlanRequest(message="10 Karten aus dem PDF", documentText="Zellen bestehen aus ...", documentName="bio.pdf", imageBase64=image)
    parts = server.attachment_parts(body)
    assert parts[0] == {"text": server.ATTACHMENT_NOTE}
    assert parts[1]["text"].startswith("Attached document (bio.pdf):") and "Zellen" in parts[1]["text"]
    assert parts[2] == {"inlineData": {"mimeType": "image/jpeg", "data": image}}


@pytest.mark.parametrize("fields, status", [
    ({"imageBase64": "@@not-base64@@"}, 400),
    ({"imageBase64": "aGk=", "mimeType": "image/heic"}, 400),
])
def test_invalid_image_attachment_is_rejected(fields, status):
    from schemas import TutorRequest

    with pytest.raises(HTTPException) as error:
        server.attachment_parts(TutorRequest(message="hi", **fields))
    assert error.value.status_code == status
