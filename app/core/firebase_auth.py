"""Firebase ID-token authentication for requests from the Flutter app.

The mobile app signs users in with Firebase Auth and keeps profiles in
Firestore, so it has no JanYukti JWT to send. Calls to the /ai router
authenticate with the Firebase ID token instead.

FIREBASE_AUTH_MODE
    off       accept requests without checking identity (local development)
    required  verify the ID token against Google's signing keys, 401 otherwise

Verification needs only the Firebase project id, not a service-account key:
ID tokens are RS256 JWTs signed with keys Google publishes at a public URL.
"""
from __future__ import annotations

import asyncio
import logging
import threading
import time
from dataclasses import dataclass, field

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from app.config import settings
from app.core.security import bearer_scheme

log = logging.getLogger(__name__)


@dataclass
class FirebaseUser:
    uid: str | None
    email: str | None = None
    verified: bool = False
    claims: dict = field(default_factory=dict)


class _CachingRequest:
    """google-auth transport that caches Google's public signing certificates.

    verify_firebase_token() downloads the certificate bundle on every call. The
    bundle rotates about daily, so an hour-long cache takes a network round trip
    out of every authenticated request without risking a stale key for long.
    """

    TTL_SECONDS = 3600

    def __init__(self) -> None:
        from google.auth.transport.requests import Request

        self._inner = Request()
        self._cache: dict[str, tuple[float, object]] = {}
        self._lock = threading.Lock()

    def __call__(self, url, method="GET", body=None, headers=None, timeout=None, **kwargs):
        cacheable = method.upper() == "GET" and body is None
        if cacheable:
            with self._lock:
                hit = self._cache.get(url)
                if hit and hit[0] > time.monotonic():
                    return hit[1]
        response = self._inner(
            url, method=method, body=body, headers=headers, timeout=timeout, **kwargs
        )
        if cacheable and getattr(response, "status", None) == 200:
            with self._lock:
                self._cache[url] = (time.monotonic() + self.TTL_SECONDS, response)
        return response


_transport: _CachingRequest | None = None
_transport_lock = threading.Lock()


def _get_transport() -> _CachingRequest:
    global _transport
    with _transport_lock:
        if _transport is None:
            _transport = _CachingRequest()
    return _transport


def verify_id_token(token: str) -> dict:
    """Return verified claims or raise. Blocking, so call it off the event loop."""
    from google.oauth2 import id_token

    project = settings.FIREBASE_PROJECT_ID
    claims = id_token.verify_firebase_token(
        token, _get_transport(), audience=project, clock_skew_in_seconds=10
    )
    if not claims:
        raise ValueError("token verified to empty claims")
    if claims.get("iss") != f"https://securetoken.google.com/{project}":
        raise ValueError("token issued for a different Firebase project")
    if not claims.get("sub"):
        raise ValueError("token has no subject")
    return claims


async def get_firebase_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> FirebaseUser:
    mode = settings.FIREBASE_AUTH_MODE.strip().lower()
    if mode == "off":
        return FirebaseUser(uid=None)
    if mode != "required":
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            f"Unknown FIREBASE_AUTH_MODE {settings.FIREBASE_AUTH_MODE!r} (use off or required)",
        )
    if not settings.FIREBASE_PROJECT_ID:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "FIREBASE_PROJECT_ID must be set when FIREBASE_AUTH_MODE=required",
        )
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing Firebase ID token")
    try:
        claims = await asyncio.to_thread(verify_id_token, creds.credentials)
    except Exception as exc:  # noqa: BLE001 - every verification failure is a 401
        log.info("Rejected Firebase ID token: %s", exc)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired Firebase ID token")
    return FirebaseUser(
        uid=claims["sub"], email=claims.get("email"), verified=True, claims=claims
    )
