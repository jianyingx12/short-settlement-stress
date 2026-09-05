from __future__ import annotations

import hashlib
import json
import os
import time
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RAW_ROOT = PROJECT_ROOT / "data" / "raw"
USER_AGENT = "short-settlement-stress/0.1 (public regulatory data research)"


class AcquisitionError(RuntimeError):
    """Raised when a source cannot be downloaded or validated."""


@dataclass(frozen=True)
class ValidationResult:
    row_count: int
    earliest_date: str
    latest_date: str
    columns: tuple[str, ...]
    anomalies: tuple[str, ...] = ()


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def parse_iso_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise AcquisitionError(f"Invalid ISO date: {value!r}") from exc


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def fetch_bytes(
    url: str,
    *,
    accept: str = "*/*",
    timeout: int = 90,
    attempts: int = 5,
) -> bytes:
    request = Request(url, headers={"Accept": accept, "User-Agent": USER_AGENT})
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            with urlopen(request, timeout=timeout) as response:
                status = getattr(response, "status", 200)
                if status != 200:
                    raise AcquisitionError(f"HTTP {status} for {url}")
                content = response.read()
                if not content:
                    raise AcquisitionError(f"Empty response from {url}")
                return content
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            last_error = exc
            if attempt < attempts:
                retry_after = None
                if isinstance(exc, HTTPError) and exc.code == 429:
                    retry_after = exc.headers.get("Retry-After")
                try:
                    delay = max(float(retry_after), 5.0 * attempt) if retry_after else 2 ** (attempt - 1)
                except ValueError:
                    delay = 5.0 * attempt
                time.sleep(min(delay, 30.0))
    raise AcquisitionError(f"Failed to download {url}: {last_error}") from last_error


def fetch_text(url: str) -> str:
    content = fetch_bytes(url, accept="text/html,application/json,text/plain")
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise AcquisitionError(f"Response from {url} is not UTF-8 text") from exc
    lowered = text.lstrip().lower()
    if lowered.startswith("<!doctype html") or lowered.startswith("<html"):
        return text
    return text


def download_validated(
    url: str,
    destination: Path,
    validator: Callable[[bytes], ValidationResult],
    *,
    force: bool = False,
) -> dict[str, Any]:
    if destination.exists() and not force:
        content = destination.read_bytes()
        result = validator(content)
        return _download_record(url, destination, content, result, "existing")

    content = fetch_bytes(url)
    lowered = content[:512].lstrip().lower()
    if lowered.startswith(b"<!doctype html") or lowered.startswith(b"<html"):
        raise AcquisitionError(f"HTML response received instead of data from {url}")
    result = validator(content)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.part")
    temporary.write_bytes(content)
    os.replace(temporary, destination)
    return _download_record(url, destination, content, result, "downloaded")


def _download_record(
    url: str,
    destination: Path,
    content: bytes,
    result: ValidationResult,
    status: str,
) -> dict[str, Any]:
    return {
        "url": url,
        "path": destination.as_posix(),
        "status": status,
        "bytes": len(content),
        "sha256": sha256_bytes(content),
        "row_count": result.row_count,
        "earliest_date": result.earliest_date,
        "latest_date": result.latest_date,
        "columns": list(result.columns),
        "anomalies": list(result.anomalies),
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.part")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def summarize_records(
    *,
    dataset: str,
    requested_start: date,
    requested_end: date,
    discovered_count: int,
    records: list[dict[str, Any]],
    missing: list[str],
    anomalies: list[str] | None = None,
) -> dict[str, Any]:
    earliest = min((r["earliest_date"] for r in records), default=None)
    latest = max((r["latest_date"] for r in records), default=None)
    return {
        "dataset": dataset,
        "generated_at": utc_now(),
        "requested_start": requested_start.isoformat(),
        "requested_end": requested_end.isoformat(),
        "discovered_files": discovered_count,
        "validated_files": len(records),
        "downloaded_files": sum(r["status"] == "downloaded" for r in records),
        "existing_files": sum(r["status"] == "existing" for r in records),
        "total_rows": sum(r["row_count"] for r in records),
        "earliest_observation": earliest,
        "latest_observation": latest,
        "missing_files": missing,
        "anomalies": anomalies or [],
        "files": records,
    }
