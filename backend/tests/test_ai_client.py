import io
import json
import urllib.error

import pytest
from fastapi import HTTPException

import ai_client
import config


def response_with(text, finish="STOP", **usage):
    return {"candidates": [{"content": {"parts": [{"text": text}]}, "finishReason": finish}], "usageMetadata": usage}


def test_parses_structured_output():
    assert ai_client.parse_gemini_output(response_with('{"reply": "hi"}')) == {"reply": "hi"}


def test_thought_parts_are_not_part_of_the_answer():
    response = {"candidates": [{"content": {"parts": [{"text": "thinking", "thought": True}, {"text": '{"reply": "hi"}'}]}}]}
    assert ai_client.parse_gemini_output(response) == {"reply": "hi"}


@pytest.mark.parametrize("response, fragment", [
    (response_with('{"cards": [{"question": "Q"', finish="MAX_TOKENS"), "cut off"),
    (response_with("", finish="MAX_TOKENS"), "cut off"),
    ({"candidates": []}, "no usable response"),
    ({}, "no usable response"),
    (response_with("not json"), "invalid structured response"),
    (response_with("[1, 2]"), "invalid structured response"),
])
def test_unusable_output_is_a_502(response, fragment):
    with pytest.raises(HTTPException) as error:
        ai_client.parse_gemini_output(response)
    assert error.value.status_code == 502
    assert fragment in error.value.detail


def test_thinking_tokens_count_as_output():
    response = response_with("{}", promptTokenCount=100, candidatesTokenCount=40, thoughtsTokenCount=60)
    assert ai_client.token_usage(response) == (100, 100)
    assert ai_client.token_usage({}) == (0, 0)
    assert ai_client.token_usage({"usageMetadata": {"promptTokenCount": None}}) == (0, 0)


def test_cost_estimate_uses_configured_rates():
    expected = 1_000_000 * config.AI_INPUT_USD_PER_MILLION / 1_000_000 + 500_000 * config.AI_OUTPUT_USD_PER_MILLION / 1_000_000
    assert ai_client.estimate_ai_cost("some-other-model", 1_000_000, 500_000) == pytest.approx(expected)


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def http_error(code):
    return urllib.error.HTTPError("https://example.invalid", code, "error", {}, io.BytesIO(b""))


def fake_urlopen(outcomes, seen):
    def urlopen(request, timeout):
        seen.append(request.full_url)
        outcome = outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return FakeResponse(json.dumps(outcome).encode())
    return urlopen


def test_falls_back_to_second_model_on_retryable_error(monkeypatch):
    seen = []
    monkeypatch.setattr(ai_client.urllib.request, "urlopen", fake_urlopen([http_error(503), response_with("{}")], seen))
    response, model = ai_client.call_gemini([{"text": "hi"}], {})
    assert model == config.GEMINI_FALLBACK_MODEL
    assert len(seen) == 2 and config.GEMINI_MODEL in seen[0] and config.GEMINI_FALLBACK_MODEL in seen[1]


def test_rejected_request_does_not_try_the_fallback(monkeypatch):
    seen = []
    monkeypatch.setattr(ai_client.urllib.request, "urlopen", fake_urlopen([http_error(400)], seen))
    with pytest.raises(HTTPException) as error:
        ai_client.call_gemini([{"text": "hi"}], {})
    assert error.value.status_code == 502 and len(seen) == 1


def test_both_models_unavailable_is_a_503(monkeypatch):
    monkeypatch.setattr(ai_client.urllib.request, "urlopen", fake_urlopen([http_error(429), http_error(503)], []))
    with pytest.raises(HTTPException) as error:
        ai_client.call_gemini([{"text": "hi"}], {})
    assert error.value.status_code == 503


def test_network_failure_is_a_502(monkeypatch):
    outcomes = [urllib.error.URLError("down"), urllib.error.URLError("down")]
    monkeypatch.setattr(ai_client.urllib.request, "urlopen", fake_urlopen(outcomes, []))
    with pytest.raises(HTTPException) as error:
        ai_client.call_gemini([{"text": "hi"}], {})
    assert error.value.status_code == 502


class Account:
    id = "account-1"
    email = "someone@example.com"


def run_execute(monkeypatch, gemini):
    events = []
    monkeypatch.setattr(ai_client, "fail_rate_limit", lambda *args, **kwargs: events.append("rate_limit"))
    monkeypatch.setattr(ai_client, "reserve_ai_usage", lambda db, account, enforce_limits=True: type("Usage", (), {"id": "usage-1"})())
    monkeypatch.setattr(ai_client, "settle_ai_usage", lambda db, usage_id, model, response: events.append("settle"))
    monkeypatch.setattr(ai_client, "release_ai_usage", lambda db, usage_id: events.append("release"))
    monkeypatch.setattr(ai_client, "call_gemini", gemini)
    try:
        return ai_client.execute_ai(None, None, Account(), [{"text": "hi"}], {}), events
    except HTTPException as error:
        return error, events


def test_successful_request_is_settled(monkeypatch):
    result, events = run_execute(monkeypatch, lambda parts, schema: (response_with('{"reply": "hi"}'), "m"))
    assert result == {"reply": "hi"} and events == ["rate_limit", "settle"]


def test_failed_upstream_call_releases_the_reservation(monkeypatch):
    def gemini(parts, schema):
        raise HTTPException(status_code=503, detail="AI service is temporarily unavailable")
    result, events = run_execute(monkeypatch, gemini)
    assert isinstance(result, HTTPException) and result.status_code == 503
    assert events == ["rate_limit", "release"]


def test_unusable_but_billed_response_is_still_settled(monkeypatch):
    result, events = run_execute(monkeypatch, lambda parts, schema: (response_with("{", finish="MAX_TOKENS"), "m"))
    assert isinstance(result, HTTPException) and result.status_code == 502
    assert events == ["rate_limit", "settle"]
