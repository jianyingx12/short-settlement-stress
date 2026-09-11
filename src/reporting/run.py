from __future__ import annotations

import argparse
from pathlib import Path

from src.sql_runner import run_sql_files


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = PROJECT_ROOT / "sql" / "reporting"
VALIDATION_FILE = PROJECT_ROOT / "sql" / "tests" / "012_power_bi_reporting_assertions.sql"


def main() -> None:
    parser = argparse.ArgumentParser(description="Refresh the Power BI reporting layer.")
    parser.add_argument("--env-file", type=Path, default=PROJECT_ROOT / ".env")
    args = parser.parse_args()

    sql_files = sorted(SQL_DIR.glob("*.sql"))
    if not sql_files:
        parser.error(f"no SQL files found in {SQL_DIR}")

    run_sql_files([*sql_files, VALIDATION_FILE], args.env_file)


if __name__ == "__main__":
    main()
