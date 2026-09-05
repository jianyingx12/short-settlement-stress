from __future__ import annotations

import csv
import io
import zipfile
from datetime import date
from pathlib import Path
from typing import Iterator

from src.ingestion.sec_ftd import EXPECTED_COLUMNS
from .common import decimal_or_none, none_if_blank


COPY_COLUMNS = (
    "settlement_date",
    "cusip",
    "symbol",
    "quantity_fails",
    "description",
    "reference_price",
    "reference_price_raw",
    "source_file",
    "source_member",
    "source_row_number",
)


def _decode_member(content: bytes) -> str:
    try:
        return content.decode("utf-8-sig")
    except UnicodeDecodeError:
        return content.decode("cp1252")


def rows(path: Path) -> Iterator[tuple[object, ...]]:
    with zipfile.ZipFile(path) as archive:
        members = sorted(name for name in archive.namelist() if not name.endswith("/"))
        for member in members:
            text = _decode_member(archive.read(member))
            reader = csv.DictReader(io.StringIO(text), delimiter="|")
            header = tuple(reader.fieldnames or ())
            if header != EXPECTED_COLUMNS:
                raise ValueError(f"Unexpected SEC FTD columns in {path.name}/{member}: {header}")
            for line_number, row in enumerate(reader, start=2):
                raw_date = row["SETTLEMENT DATE"].strip()
                if raw_date.casefold().startswith("trailer"):
                    continue
                raw_price = row["PRICE"].strip()
                yield (
                    date(int(raw_date[:4]), int(raw_date[4:6]), int(raw_date[6:8])),
                    none_if_blank(row["CUSIP"]),
                    none_if_blank(row["SYMBOL"]),
                    int(row["QUANTITY (FAILS)"]),
                    none_if_blank(row["DESCRIPTION"]),
                    decimal_or_none(raw_price),
                    raw_price,
                    path.name,
                    member,
                    line_number,
                )


def files(raw_root: Path) -> tuple[Path, ...]:
    return tuple(sorted((raw_root / "sec_ftd").glob("cnsfails*.zip")))
