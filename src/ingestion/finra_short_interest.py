from __future__ import annotations

import argparse
import csv
import io
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

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


PARTITIONS_URL = (
    "https://api.finra.org/partitions/group/otcmarket/name/consolidatedShortInterest"
)
FILE_URL = "https://cdn.finra.org/equity/otcmarket/biweekly/shrt{date}.csv"
EXPECTED_COLUMNS = (
    "accountingYearMonthNumber",
    "symbolCode",
    "issueName",
    "issuerServicesGroupExchangeCode",
    "marketClassCode",
    "currentShortPositionQuantity",
    "previousShortPositionQuantity",
    "stockSplitFlag",
    "averageDailyVolumeQuantity",
    "daysToCoverQuantity",
    "revisionFlag",
    "changePercent",
    "changePreviousNumber",
    "settlementDate",
)
NUMERIC_FIELDS = (
    "currentShortPositionQuantity",
    "previousShortPositionQuantity",
    "averageDailyVolumeQuantity",
    "daysToCoverQuantity",
    "changePercent",
    "changePreviousNumber",
)


def parse_partitions(payload: str) -> list[date]:
    try:
        document = json.loads(payload)
        values = document["availablePartitions"]
        dates = [date.fromisoformat(item["partitions"][0]) for item in values]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError) as exc:
        raise AcquisitionError("Unexpected FINRA short-interest partition response") from exc
    if not dates:
        raise AcquisitionError("FINRA short-interest partition response is empty")
    return sorted(set(dates))


def discover_cycles(start: date, end: date) -> list[tuple[date, str]]:
    partitions = parse_partitions(fetch_text(PARTITIONS_URL))
    return [
        (cycle, FILE_URL.format(date=cycle.strftime("%Y%m%d")))
        for cycle in partitions
        if start <= cycle <= end
    ]


def validate_short_interest(
    content: bytes, expected_date: date | None = None
) -> ValidationResult:
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise AcquisitionError("Short-interest file is not UTF-8 text") from exc
    if text.lstrip().lower().startswith(("<!doctype html", "<html")):
        raise AcquisitionError("Short-interest response is HTML, not data")

    reader = csv.DictReader(io.StringIO(text), delimiter="|")
    actual = tuple(reader.fieldnames or ())
    if actual != EXPECTED_COLUMNS:
        raise AcquisitionError(f"Unexpected short-interest columns: {actual}")

    row_count = 0
    dates: list[date] = []
    for line_number, row in enumerate(reader, start=2):
        row_count += 1
        try:
            settlement = date.fromisoformat(row["settlementDate"])
            accounting = datetime.strptime(
                row["accountingYearMonthNumber"], "%Y%m%d"
            ).date()
        except (TypeError, ValueError) as exc:
            raise AcquisitionError(f"Invalid date on short-interest row {line_number}") from exc
        if settlement != accounting:
            raise AcquisitionError(f"Conflicting dates on short-interest row {line_number}")
        if expected_date and settlement != expected_date:
            raise AcquisitionError(
                f"Short-interest row date {settlement} does not match {expected_date}"
            )
        if not row["symbolCode"].strip():
            raise AcquisitionError(f"Blank symbol on short-interest row {line_number}")
        for field in NUMERIC_FIELDS:
            value = row[field].strip()
            if not value:
                continue
            try:
                Decimal(value)
            except InvalidOperation as exc:
                raise AcquisitionError(
                    f"Invalid {field} value on short-interest row {line_number}: {value!r}"
                ) from exc
        dates.append(settlement)

    if not row_count:
        raise AcquisitionError("Short-interest file contains no rows")
    return ValidationResult(
        row_count=row_count,
        earliest_date=min(dates).isoformat(),
        latest_date=max(dates).isoformat(),
        columns=EXPECTED_COLUMNS,
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
    cycles = discover_cycles(start, end)
    selected = cycles[:limit] if limit else cycles
    records: list[dict] = []

    def task(item: tuple[date, str]) -> dict:
        cycle, url = item
        destination = raw_dir / f"shrt{cycle:%Y%m%d}.csv"
        return download_validated(
            url,
            destination,
            lambda content: validate_short_interest(content, cycle),
            force=force,
        )

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(task, item): item for item in selected}
        for future in as_completed(futures):
            records.append(future.result())

    records.sort(key=lambda row: row["path"])
    expected_names = {f"shrt{cycle:%Y%m%d}.csv" for cycle, _ in selected}
    present_names = {Path(row["path"]).name for row in records}
    summary = summarize_records(
        dataset="FINRA Consolidated Short Interest",
        requested_start=start,
        requested_end=end,
        discovered_count=len(cycles),
        records=records,
        missing=sorted(expected_names - present_names),
        anomalies=(
            [f"Run limited to {limit} of {len(cycles)} discovered cycles"]
            if limit and limit < len(cycles)
            else []
        ),
    )
    write_json(raw_dir / "coverage.json", summary)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", default="2018-08-01")
    parser.add_argument("--end", default=date.today().isoformat())
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW_ROOT / "finra_short_interest")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limit", type=int, help="Download only the first N cycles (smoke tests)")
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
