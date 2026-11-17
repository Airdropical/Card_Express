import hashlib
import json
import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException

import apple_auth
import config
import profiles
import server

KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
NONCE = "a-random-nonce-from-the-app"


@pytest.fixture(autouse=True)
def apple_keys(monkeypatch):
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(KEY.public_key()))
    monkeypatch.setattr(apple_auth, "apple_public_keys", lambda force=False: {"key-1": jwk})


def identity_token(key=KEY, kid="key-1", **overrides):
    claims = {
        "iss": apple_auth.APPLE_ISSUER, "aud": config.APPLE_BUNDLE_ID, "sub": "001234.abc",
        "iat": int(time.time()), "exp": int(time.time()) + 600,
        "nonce": hashlib.sha256(NONCE.encode()).hexdigest(), "email": "Ian@Example.com", "email_verified": "true",
    }
    claims.update(overrides)
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": kid})


def test_valid_identity_token_is_accepted():
    claims = apple_auth.verify_identity_token(identity_token(), NONCE)
    assert claims["sub"] == "001234.abc"
    assert apple_auth.verified_email(claims) == "ian@example.com"


@pytest.mark.parametrize("token, nonce", [
    (identity_token(aud="com.someone.else"), NONCE),
    (identity_token(iss="https://evil.example"), NONCE),
    (identity_token(exp=int(time.time()) - 10), NONCE),
    (identity_token(key=OTHER_KEY), NONCE),
    (identity_token(kid="unknown-key"), NONCE),
    (identity_token(sub=""), NONCE),
    (identity_token(), "a-different-nonce"),
    ("not-a-token", NONCE),
])
def test_invalid_identity_tokens_are_rejected(token, nonce):
    with pytest.raises(HTTPException) as error:
        apple_auth.verify_identity_token(token, nonce)
    assert error.value.status_code == 401


def test_unverified_or_missing_email_is_not_used():
    assert apple_auth.verified_email({"email": "a@example.com", "email_verified": "false"}) is None
    assert apple_auth.verified_email({"email": "a@example.com"}) is None
    assert apple_auth.verified_email({"email_verified": True}) is None
    assert apple_auth.verified_email({"email": "a@example.com", "email_verified": True}) == "a@example.com"


def test_revocation_is_skipped_without_configuration(monkeypatch):
    monkeypatch.setattr(config, "APPLE_TEAM_ID", "")
    called = []
    monkeypatch.setattr(apple_auth, "_post_form", lambda *args: called.append(args))
    assert apple_auth.refresh_token_for("code") is None
    apple_auth.revoke("refresh-token")
    assert called == []


class FakeSession:
    """Stands in for the database: answers the two account lookups and records what was added."""

    def __init__(self, by_sub=None, by_email=None):
        self.by_sub, self.by_email, self.added = by_sub, by_email, []

    def scalar(self, statement):
        column = str(statement.whereclause.left.name)
        return self.by_sub if column == "apple_sub" else self.by_email

    def add(self, item):
        self.added.append(item)


def test_known_apple_identity_returns_its_account():
    account = server.Account(email="x@example.com", apple_sub="sub-1")
    db = FakeSession(by_sub=account)
    assert server.account_for_apple_identity(db, "sub-1", "x@example.com") is account
    assert db.added == []


def test_existing_password_account_is_linked_by_verified_email():
    account = server.Account(email="ian@example.com", password_hash="hash", apple_sub=None)
    db = FakeSession(by_email=account)
    assert server.account_for_apple_identity(db, "sub-1", "ian@example.com") is account
    assert account.apple_sub == "sub-1" and db.added == []


def test_new_apple_identity_creates_account_and_empty_profile():
    db = FakeSession()
    account = server.account_for_apple_identity(db, "sub-1", "new@example.com")
    assert account.email == "new@example.com" and account.password_hash is None and account.apple_sub == "sub-1"
    assert len(db.added) == 2 and db.added[1].document is None and db.added[1].revision == 0


def test_hidden_or_taken_email_gets_a_placeholder_address():
    assert server.account_for_apple_identity(FakeSession(), "sub-1", None).email == "sub-1@apple.invalid"
    taken = server.Account(email="ian@example.com", apple_sub="someone-else")
    assert server.account_for_apple_identity(FakeSession(by_email=taken), "sub-2", "ian@example.com").email == "sub-2@apple.invalid"


def snapshot(**overrides):
    document = {"schemaVersion": 1, "decks": [{"id": "d", "name": "Bio", "cards": []}], "vocabulary": [], "studyDays": [784000000.0]}
    document.update(overrides)
    return document


def test_snapshot_is_accepted_unchanged():
    document = snapshot(futureField={"kept": True})
    assert profiles.validate_snapshot(document) is document


@pytest.mark.parametrize("document", [
    {"decks": [], "vocabulary": []},
    snapshot(decks="nope"),
    snapshot(decks=["not an object"]),
    snapshot(schemaVersion="1"),
])
def test_malformed_snapshot_is_rejected(document):
    with pytest.raises(HTTPException) as error:
        profiles.validate_snapshot(document)
    assert error.value.status_code == 422


def test_oversized_snapshot_is_rejected(monkeypatch):
    monkeypatch.setattr(profiles, "MAX_PROFILE_BYTES", 200)
    with pytest.raises(HTTPException) as error:
        profiles.validate_snapshot(snapshot(decks=[{"name": "x" * 500}]))
    assert error.value.status_code == 413
