from __future__ import annotations

import argparse
import csv
import io
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from decimal import Decimal, InvalidOperation
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode

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


SOURCE_PAGE = (
    "https://www.finra.org/finra-data/browse-catalog/short-sale-volume-data/"
    "daily-short-sale-volume-files"
)
FILE_PATTERN = re.compile(r"CNMSshvol(?P<date>\d{8})(?:v\d+)?\.txt$", re.I)
EXPECTED_COLUMNS = (
    "Date",
    "Symbol",
    "ShortVolume",
    "ShortExemptVolume",
    "TotalVolume",
    "Market",
)


class _ArchiveParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.year_values: dict[int, str] = {}
        self.links: list[str] = []
        self._year_select = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "select":
            self._year_select = values.get("name") == "custom_year[year]"
        elif tag == "option" and self._year_select:
            self._option_value = values.get("value")
        elif tag == "a" and values.get("href"):
            href = values["href"]
            if href and "CNMSshvol" in href:
                self.links.append(href)

    def handle_endtag(self, tag: str) -> None:
        if tag == "select":
            self._year_select = False

    def handle_data(self, data: str) -> None:
        if self._year_select and hasattr(self, "_option_value"):
            label = data.strip()
            if label.isdigit() and len(label) == 4:
                self.year_values[int(label)] = self._option_value
            del self._option_value


def parse_archive_page(html: str) -> tuple[dict[int, str], list[str]]:
    parser = _ArchiveParser()
    parser.feed(html)
    return parser.year_values, sorted(set(parser.links))


def _cached_page(url: str, path: Path, *, refresh: bool) -> tuple[str, bool]:
    if path.exists() and not refresh:
        return path.read_text(encoding="utf-8"), False
    html = fetch_text(url)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.part")
    temporary.write_text(html, encoding="utf-8")
    os.replace(temporary, path)
    return html, True


def discover_files(
    start: date,
    end: date,
    index_dir: Path | None = None,
    *,
    refresh_index: bool = False,
    request_delay: float = 20.0,
) -> list[tuple[date, str]]:
    index_dir = index_dir or DEFAULT_RAW_ROOT / "finra_short_volume" / "source_pages"
    selector_html, fetched = _cached_page(
        SOURCE_PAGE, index_dir / "selector.html", refresh=refresh_index
    )
    years, _ = parse_archive_page(selector_html)
    missing_years = [year for year in range(start.year, end.year + 1) if year not in years]
    if missing_years:
        raise AcquisitionError(f"FINRA archive has no selector values for years {missing_years}")

    discovered: dict[str, tuple[date, str]] = {}
    for year in range(start.year, end.year + 1):
        if fetched and request_delay:
            time.sleep(request_delay)
        query = urlencode(
            {
                "custom_month[month]": "any",
                "custom_year[year]": years[year],
            }
        )
        html, fetched = _cached_page(
            f"{SOURCE_PAGE}?{query}",
            index_dir / f"{year}.html",
            refresh=refresh_index,
        )
        _, links = parse_archive_page(html)
        if not links:
            raise AcquisitionError(f"FINRA archive returned no Consolidated NMS links for {year}")
        for url in links:
            name = url.rsplit("/", 1)[-1]
            match = FILE_PATTERN.fullmatch(name)
            if not match:
                continue
            file_date = date.fromisoformat(
                f"{match['date'][:4]}-{match['date'][4:6]}-{match['date'][6:]}"
            )
            if start <= file_date <= end:
                discovered[url] = (file_date, url)
    return sorted(discovered.values())


def validate_short_volume(content: bytes, expected_date: date | None = None) -> ValidationResult:
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise AcquisitionError("Short-volume file is not UTF-8 text") from exc
    if text.lstrip().lower().startswith(("<!doctype html", "<html")):
        raise AcquisitionError("Short-volume response is HTML, not data")

    rows = list(csv.reader(io.StringIO(text), delimiter="|"))
    if not rows or tuple(rows[0]) != EXPECTED_COLUMNS:
        actual = tuple(rows[0]) if rows else ()
        raise AcquisitionError(f"Unexpected short-volume columns: {actual}")
    if len(rows) < 3 or len(rows[-1]) != 1 or not rows[-1][0].isdigit():
        raise AcquisitionError("Short-volume file has no valid trailer count")

    data_rows = rows[1:-1]
    trailer_count = int(rows[-1][0])
    if trailer_count != len(data_rows):
        raise AcquisitionError(
            f"Short-volume trailer says {trailer_count} rows; parsed {len(data_rows)}"
        )

    dates: list[date] = []
    for line_number, row in enumerate(data_rows, start=2):
        if len(row) != len(EXPECTED_COLUMNS):
            raise AcquisitionError(f"Short-volume row {line_number} has {len(row)} fields")
        try:
            row_date = date(int(row[0][:4]), int(row[0][4:6]), int(row[0][6:8]))
        except (ValueError, IndexError) as exc:
            raise AcquisitionError(f"Invalid date on short-volume row {line_number}") from exc
        if expected_date and row_date != expected_date:
            raise AcquisitionError(
                f"Short-volume row date {row_date} does not match {expected_date}"
            )
        if not row[1].strip():
            raise AcquisitionError(f"Blank symbol on short-volume row {line_number}")
        for value in row[2:5]:
            try:
                if Decimal(value) < 0:
                    raise ValueError
            except (InvalidOperation, ValueError) as exc:
                raise AcquisitionError(
                    f"Invalid quantity {value!r} on short-volume row {line_number}"
                ) from exc
        dates.append(row_date)

    if not dates:
        raise AcquisitionError("Short-volume file contains no data rows")
    return ValidationResult(
        row_count=len(data_rows),
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
    refresh_index: bool = False,
) -> dict:
    files = discover_files(
        start,
        end,
        raw_dir / "source_pages",
        refresh_index=refresh_index,
    )
    selected = files[:limit] if limit else files
    records: list[dict] = []

    def task(item: tuple[date, str]) -> dict:
        file_date, url = item
        destination = raw_dir / url.rsplit("/", 1)[-1]
        return download_validated(
            url,
            destination,
            lambda content: validate_short_volume(content, file_date),
            force=force,
        )

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(task, item): item for item in selected}
        for future in as_completed(futures):
            records.append(future.result())

    records.sort(key=lambda row: row["path"])
    expected_names = {url.rsplit("/", 1)[-1] for _, url in selected}
    present_names = {Path(row["path"]).name for row in records}
    summary = summarize_records(
        dataset="FINRA Consolidated NMS Daily Short Sale Volume",
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
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW_ROOT / "finra_short_volume")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument(
        "--refresh-index",
        action="store_true",
        help="Refetch cached FINRA archive index pages",
    )
    parser.add_argument("--limit", type=int, help="Download only the first N files (smoke tests)")
    args = parser.parse_args()
    summary = acquire(
        parse_iso_date(args.start),
        parse_iso_date(args.end),
        args.raw_dir,
        workers=args.workers,
        force=args.force,
        limit=args.limit,
        refresh_index=args.refresh_index,
    )
    print(
        f"Validated {summary['validated_files']} files and {summary['total_rows']} rows "
        f"from {summary['earliest_observation']} to {summary['latest_observation']}."
    )


if __name__ == "__main__":
    main()
