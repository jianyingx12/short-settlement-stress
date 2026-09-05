from __future__ import annotations

import csv
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Iterator

from src.ingestion.finra_short_interest import EXPECTED_COLUMNS
from .common import none_if_blank


COPY_COLUMNS = (
    "accounting_year_month_number",
    "symbol_code",
    "issue_name",
    "issuer_services_group_exchange_code",
    "market_class_code",
    "current_short_position_quantity",
    "previous_short_position_quantity",
    "stock_split_flag",
    "average_daily_volume_quantity",
    "days_to_cover_quantity",
    "revision_flag",
    "change_percent",
    "change_previous_number",
    "settlement_date",
    "source_file",
    "source_row_number",
)


def _decimal(value: str | None) -> Decimal | None:
    return Decimal(value) if value and value.strip() else None


def rows(path: Path) -> Iterator[tuple[object, ...]]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source, delimiter="|")
        header = tuple(reader.fieldnames or ())
        if header != EXPECTED_COLUMNS:
            raise ValueError(f"Unexpected short-interest columns in {path.name}: {header}")
        for line_number, row in enumerate(reader, start=2):
            yield (
                int(row["accountingYearMonthNumber"]),
                row["symbolCode"].strip(),
                none_if_blank(row["issueName"]),
                none_if_blank(row["issuerServicesGroupExchangeCode"]),
                none_if_blank(row["marketClassCode"]),
                _decimal(row["currentShortPositionQuantity"]),
                _decimal(row["previousShortPositionQuantity"]),
                none_if_blank(row["stockSplitFlag"]),
                _decimal(row["averageDailyVolumeQuantity"]),
                _decimal(row["daysToCoverQuantity"]),
                none_if_blank(row["revisionFlag"]),
                _decimal(row["changePercent"]),
                _decimal(row["changePreviousNumber"]),
                date.fromisoformat(row["settlementDate"]),
                path.name,
                line_number,
            )


def files(raw_root: Path) -> tuple[Path, ...]:
    return tuple(sorted((raw_root / "finra_short_interest").glob("shrt*.csv")))
