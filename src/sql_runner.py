from __future__ import annotations

import time
from pathlib import Path

from src.loading.common import read_database_settings


def run_sql_files(sql_files: list[Path], env_file: Path) -> None:
    try:
        import psycopg
    except ImportError as exc:
        raise RuntimeError("Install database dependencies with: pip install -r requirements.txt") from exc

    settings = read_database_settings(env_file)
    with psycopg.connect(**settings, autocommit=True) as connection:
        for path in sql_files:
            started = time.perf_counter()
            with connection.cursor() as cursor:
                cursor.execute(path.read_text(encoding="utf-8"))
            elapsed = time.perf_counter() - started
            print(f"{path.name}: {elapsed:.1f}s", flush=True)
