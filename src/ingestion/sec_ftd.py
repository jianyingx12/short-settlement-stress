from __future__ import annotations

import argparse
import csv
import io
import re
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from decimal import Decimal, InvalidOperation
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin

from .common import (
    DEFAULT_RAW_ROOT,
    AcquisitionError,
    ValidationResult,
    download_validated,
    fetch_text,
    parse_iso_date,
    summarize_records,
    write_json,
)


SOURCE_PAGE = "https://www.sec.gov/data-research/sec-markets-data/fails-deliver-data"
FILE_PATTERN = re.compile(r"cnsfails(?P<year>\d{4})(?P<month>\d{2})(?P<half>[ab])\.zip$", re.I)
EXPECTED_COLUMNS = (
    "SETTLEMENT DATE",
    "CUSIP",
    "SYMBOL",
    "QUANTITY (FAILS)",
    "DESCRIPTION",
    "PRICE",
)


class _LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "a" and values.get("href"):
            href = values["href"]
            if href and FILE_PATTERN.search(href):
                self.links.append(href)


def parse_source_links(html: str) -> list[str]:
    parser = _LinkParser()
    parser.feed(html)
    return sorted({urljoin(SOURCE_PAGE, href) for href in parser.links})


def _period_bounds(url: str) -> tuple[date, date]:
    match = FILE_PATTERN.search(url)
    if not match:
        raise AcquisitionError(f"Unrecognized SEC FTD filename: {url}")
    year, month = int(match["year"]), int(match["month"])
    if match["half"].lower() == "a":
        return date(year, month, 1), date(year, month, 15)
    if month == 12:
        next_month = date(year + 1, 1, 1)
    else:
        next_month = date(year, month + 1, 1)
    return date(year, month, 16), next_month.fromordinal(next_month.toordinal() - 1)


def discover_files(start: date, end: date) -> list[str]:
    links = parse_source_links(fetch_text(SOURCE_PAGE))
    selected = []
    for url in links:
        period_start, period_end = _period_bounds(url)
        if period_end >= start and period_start <= end:
            selected.append(url)
    if not selected:
        raise AcquisitionError("No SEC FTD files discovered for the requested period")
    return selected


def validate_ftd_zip(content: bytes) -> ValidationResult:
    if not content.startswith(b"PK"):
        raise AcquisitionError("SEC FTD response is not a ZIP archive")
    try:
        archive = zipfile.ZipFile(io.BytesIO(content))
    except zipfile.BadZipFile as exc:
        raise AcquisitionError("SEC FTD ZIP archive is corrupt") from exc
    bad_member = archive.testzip()
    if bad_member:
        raise AcquisitionError(f"SEC FTD ZIP member failed CRC: {bad_member}")

    members = [name for name in archive.namelist() if not name.endswith("/")]
    if not members:
        raise AcquisitionError("SEC FTD ZIP contains no files")

    row_count = 0
    dates: list[date] = []
    observed_columns: tuple[str, ...] | None = None
    anomalies: list[str] = []
    trailer_types: set[str] = set()
    total_quantity = 0
    blank_cusip_count = 0
    blank_symbol_count = 0
    for member in members:
        raw_member = archive.read(member)
        try:
            text = raw_member.decode("utf-8-sig")
        except UnicodeDecodeError:
            # Historical SEC files include Windows-1252 issuer-name bytes.
            text = raw_member.decode("cp1252")
            anomalies.append(f"{member} decoded as Windows-1252")
        reader = csv.DictReader(io.StringIO(text), delimiter="|")
        actual = tuple(reader.fieldnames or ())
        if actual != EXPECTED_COLUMNS:
            raise AcquisitionError(f"Unexpected SEC FTD columns in {member}: {actual}")
        observed_columns = actual
        for line_number, row in enumerate(reader, start=2):
            raw_date = row["SETTLEMENT DATE"]
            if raw_date.strip().casefold().startswith("trailer"):
                trailer_text = "|".join(value or "" for value in row.values()).strip("|")
                match = re.fullmatch(r"Trailer record count (\d+)", trailer_text, re.I)
                if match:
                    trailer_type = "record count"
                    actual_value = row_count
                else:
                    match = re.fullmatch(
                        r"Trailer total quantity of shares (\d+)", trailer_text, re.I
                    )
                    trailer_type = "total quantity"
                    actual_value = total_quantity
                if not match or int(match.group(1)) != actual_value:
                    raise AcquisitionError(
                        f"Invalid trailer control total in {member}: {trailer_text!r}"
                    )
                if trailer_type in trailer_types:
                    raise AcquisitionError(
                        f"Duplicate {trailer_type} trailer in {member}"
                    )
                trailer_types.add(trailer_type)
                continue
            row_count += 1
            try:
                settlement = date(
                    int(raw_date[:4]), int(raw_date[4:6]), int(raw_date[6:8])
                )
                quantity = int(row["QUANTITY (FAILS)"])
                if quantity < 0:
                    raise ValueError
            except (TypeError, ValueError, IndexError) as exc:
                raise AcquisitionError(
                    f"Invalid date or quantity in {member} row {line_number}"
                ) from exc
            price = row["PRICE"].strip()
            if price and price != ".":
                try:
                    Decimal(price)
                except InvalidOperation as exc:
                    raise AcquisitionError(
                        f"Invalid price in {member} row {line_number}: {price!r}"
                    ) from exc
            if not row["CUSIP"].strip():
                blank_cusip_count += 1
            if not row["SYMBOL"].strip():
                blank_symbol_count += 1
            total_quantity += quantity
            dates.append(settlement)

    if not row_count or not dates or observed_columns is None:
        raise AcquisitionError("SEC FTD archive contains no data rows")
    if trailer_types:
        anomalies.append(
            f"{member} contains validated {', '.join(sorted(trailer_types))} trailers"
        )
    if blank_cusip_count:
        anomalies.append(f"{blank_cusip_count} rows have blank CUSIP")
    if blank_symbol_count:
        anomalies.append(f"{blank_symbol_count} rows have blank symbol")
    return ValidationResult(
        row_count=row_count,
        earliest_date=min(dates).isoformat(),
        latest_date=max(dates).isoformat(),
        columns=observed_columns,
        anomalies=tuple(anomalies),
    )


def acquire(
    start: date,
    end: date,
    raw_dir: Path,
    *,
    workers: int = 4,
    force: bool = False,
    limit: int | None = None,
) -> dict:
    files = discover_files(start, end)
    selected = files[:limit] if limit else files
    records: list[dict] = []

    def task(url: str) -> dict:
        destination = raw_dir / url.rsplit("/", 1)[-1]
        return download_validated(url, destination, validate_ftd_zip, force=force)

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(task, url): url for url in selected}
        for future in as_completed(futures):
            records.append(future.result())

    records.sort(key=lambda row: row["path"])
    expected_names = {url.rsplit("/", 1)[-1] for url in selected}
    present_names = {Path(row["path"]).name for row in records}
    summary = summarize_records(
        dataset="SEC Fails-to-Deliver",
        requested_start=start,
        requested_end=end,
        discovered_count=len(files),
        records=records,
        missing=sorted(expected_names - present_names),
        anomalies=(
            [f"Run limited to {limit} of {len(files)} discovered files"]
            if limit and limit < len(files)
            else []
        ),
    )
    write_json(raw_dir / "coverage.json", summary)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", default="2018-08-01")
    parser.add_argument("--end", default=date.today().isoformat())
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW_ROOT / "sec_ftd")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limit", type=int, help="Download only the first N files (smoke tests)")
    args = parser.parse_args()
    summary = acquire(
        parse_iso_date(args.start),
        parse_iso_date(args.end),
        args.raw_dir,
        workers=args.workers,
        force=args.force,
        limit=args.limit,
    )
    print(
        f"Validated {summary['validated_files']} files and {summary['total_rows']} rows "
        f"from {summary['earliest_observation']} to {summary['latest_observation']}."
    )


if __name__ == "__main__":
    main()
