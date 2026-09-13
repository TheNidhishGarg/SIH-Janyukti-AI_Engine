"""Thin Gemini wrapper returning parsed JSON, or None if the LLM is unusable.

Every caller must handle None - that is what makes the heuristic fallbacks
mandatory rather than decorative. Runs the blocking SDK call in a thread so it
does not stall the event loop.
"""
from __future__ import annotations

import asyncio
import json
import logging
import re
import threading

from app.config import settings

log = logging.getLogger(__name__)

_client = None
_client_lock = threading.Lock()
_client_failed = False


def is_available() -> bool:
    return bool(settings.GEMINI_API_KEY) and not _client_failed


def _get_client():
    global _client, _client_failed
    if _client is not None or _client_failed:
        return _client
    if not settings.GEMINI_API_KEY:
        _client_failed = True
        return None
    with _client_lock:
        if _client is not None or _client_failed:
            return _client
        try:
            import google.generativeai as genai

            genai.configure(api_key=settings.GEMINI_API_KEY)
            _client = genai.GenerativeModel(settings.GEMINI_MODEL)
        except Exception as exc:  # noqa: BLE001
            log.warning("Gemini unavailable (%s); heuristic engine will be used", exc)
            _client_failed = True
    return _client


_JSON_BLOCK = re.compile(r"\{.*\}", re.DOTALL)


def _parse_json(raw: str) -> dict | None:
    """Models sometimes wrap JSON in prose or fences - pull out the object."""
    raw = raw.strip()
    if raw.startswith("```"):
        raw = re.sub(r"^```(?:json)?|```$", "", raw, flags=re.MULTILINE).strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        pass
    match = _JSON_BLOCK.search(raw)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            return None
    return None


def _generate_sync(prompt: str, temperature: float) -> dict | None:
    client = _get_client()
    if client is None:
        return None
    try:
        response = client.generate_content(
            prompt,
            generation_config={
                "temperature": temperature,
                "response_mime_type": "application/json",
            },
        )
        return _parse_json(response.text or "")
    except Exception as exc:  # noqa: BLE001
        log.warning("Gemini call failed (%s); falling back to heuristics", exc)
        return None


async def generate_json(prompt: str, temperature: float = 0.1, timeout: float = 20.0) -> dict | None:
    if not is_available():
        return None
    try:
        return await asyncio.wait_for(asyncio.to_thread(_generate_sync, prompt, temperature), timeout)
    except asyncio.TimeoutError:
        log.warning("Gemini call timed out after %.0fs; falling back to heuristics", timeout)
        return None
