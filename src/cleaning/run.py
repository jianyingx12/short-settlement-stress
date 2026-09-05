from __future__ import annotations

import argparse
import time
from pathlib import Path

from src.loading.common import read_database_settings


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SQL_DIR = PROJECT_ROOT / "sql" / "cleaning"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the cleaned analytical tables.")
    parser.add_argument("--env-file", type=Path, default=PROJECT_ROOT / ".env")
    parser.add_argument("--sql-dir", type=Path, default=DEFAULT_SQL_DIR)
    parser.add_argument(
        "--summaries-only",
        action="store_true",
        help="Refresh the quality, identity, and coverage summaries without rebuilding base tables.",
    )
    args = parser.parse_args()

    sql_files = sorted(args.sql_dir.glob("*.sql"))
    if args.summaries_only:
        if args.sql_dir.resolve() != DEFAULT_SQL_DIR.resolve():
            parser.error("--summaries-only can only be used with the default cleaning SQL directory")
        sql_files = [path for path in sql_files if path.name[:3] in {"007", "008", "009"}]
    if not sql_files:
        parser.error(f"no SQL files found in {args.sql_dir}")

    try:
        import psycopg
    except ImportError as exc:
        raise RuntimeError("Install database dependencies with: pip install -r requirements.txt") from exc

    settings = read_database_settings(args.env_file)
    with psycopg.connect(**settings, autocommit=True) as connection:
        for path in sql_files:
            started = time.perf_counter()
            with connection.cursor() as cursor:
                cursor.execute(path.read_text(encoding="utf-8"))
            elapsed = time.perf_counter() - started
            print(f"{path.name}: {elapsed:.1f}s", flush=True)


if __name__ == "__main__":
    main()
