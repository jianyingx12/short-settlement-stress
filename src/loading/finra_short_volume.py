from __future__ import annotations

import csv
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Iterator

from src.ingestion.finra_short_volume import EXPECTED_COLUMNS


COPY_COLUMNS = (
    "trade_date",
    "symbol",
    "short_volume",
    "short_exempt_volume",
    "total_volume",
    "market",
    "source_file",
    "source_row_number",
)


def rows(path: Path) -> Iterator[tuple[object, ...]]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.reader(source, delimiter="|")
        header = tuple(next(reader, ()))
        if header != EXPECTED_COLUMNS:
            raise ValueError(f"Unexpected short-volume columns in {path.name}: {header}")
        for line_number, row in enumerate(reader, start=2):
            if len(row) == 1 and row[0].isdigit():
                continue
            if len(row) != len(EXPECTED_COLUMNS):
                raise ValueError(f"Malformed short-volume row {line_number} in {path.name}")
            yield (
                date(int(row[0][:4]), int(row[0][4:6]), int(row[0][6:8])),
                row[1].strip(),
                Decimal(row[2]),
                Decimal(row[3]),
                Decimal(row[4]),
                row[5].strip(),
                path.name,
                line_number,
            )


def files(raw_root: Path) -> tuple[Path, ...]:
    return tuple(sorted((raw_root / "finra_short_volume").glob("CNMSshvol*.txt")))
