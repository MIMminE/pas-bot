from __future__ import annotations

import base64
import json
import ssl
from typing import Any
from urllib import request
from urllib.error import HTTPError, URLError


def basic_auth_header(username: str, token: str) -> str:
    raw = f"{username}:{token}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("ascii")


def json_request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
    timeout: int = 30,
) -> Any:
    data = None
    merged_headers = {"Accept": "application/json"}
    if headers:
        merged_headers.update(headers)
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        merged_headers["Content-Type"] = "application/json"

    req = request.Request(url, data=data, headers=merged_headers, method=method.upper())
    try:
        with request.urlopen(req, timeout=timeout, context=_ssl_context()) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body else None
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} failed with HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        reason = getattr(exc, "reason", exc)
        if isinstance(reason, ssl.SSLCertVerificationError):
            raise RuntimeError(
                "HTTPS 인증서 검증에 실패했습니다. "
                "네트워크 프록시/보안 프로그램이 인증서를 바꾸고 있거나, 앱에 CA 인증서 번들이 포함되지 않았을 수 있습니다. "
                f"상세: {reason}"
            ) from exc
        raise RuntimeError(f"{method} {url} 요청에 실패했습니다: {reason}") from exc


def _ssl_context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        return ssl.create_default_context()
