from __future__ import annotations

import argparse
from pathlib import Path

from src.sql_runner import run_sql_files


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SQL_DIR = PROJECT_ROOT / "sql" / "analysis"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build short-interest cycle analysis.")
    parser.add_argument("--env-file", type=Path, default=PROJECT_ROOT / ".env")
    args = parser.parse_args()

    sql_files = sorted(DEFAULT_SQL_DIR.glob("*.sql"))
    if not sql_files:
        parser.error(f"no SQL files found in {DEFAULT_SQL_DIR}")

    run_sql_files(sql_files, args.env_file)


if __name__ == "__main__":
    main()
