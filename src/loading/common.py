from __future__ import annotations

import hashlib
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Callable, Iterator


@dataclass(frozen=True)
class LoadJob:
    dataset: str
    table: str
    columns: tuple[str, ...]
    files: tuple[Path, ...]
    read_rows: Callable[[Path], Iterator[tuple[object, ...]]]


def read_database_settings(path: Path) -> dict[str, object]:
    if not path.exists():
        raise RuntimeError(f"Database environment file not found: {path}")

    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator:
            raise RuntimeError(f"Invalid environment line in {path}: {raw_line!r}")
        values[key.strip()] = value.strip().strip('"').strip("'")

    required = ("DB_NAME", "DB_USER", "DB_PASSWORD")
    missing = [key for key in required if not values.get(key)]
    if missing:
        raise RuntimeError(f"Missing database settings in {path}: {', '.join(missing)}")

    return {
        "dbname": values["DB_NAME"],
        "user": values["DB_USER"],
        "password": values["DB_PASSWORD"],
        "host": values.get("DB_HOST", "localhost"),
        "port": int(values.get("DB_PORT", "5432")),
    }


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_dataset(connection: object, job: LoadJob) -> tuple[int, int]:
    from psycopg import sql

    loaded_files = 0
    skipped_files = 0
    copy_statement = sql.SQL("COPY {}.{} ({}) FROM STDIN").format(
        sql.Identifier("market_structure"),
        sql.Identifier(job.table),
        sql.SQL(", ").join(map(sql.Identifier, job.columns)),
    )

    for path in job.files:
        checksum = file_sha256(path)
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT source_sha256
                FROM market_structure.ingestion_file
                WHERE dataset = %s AND source_file = %s
                """,
                (job.dataset, path.name),
            )
            existing = cursor.fetchone()

        if existing and existing[0] == checksum:
            skipped_files += 1
            continue

        with connection.transaction():
            with connection.cursor() as cursor:
                if existing:
                    cursor.execute(
                        sql.SQL("DELETE FROM {}.{} WHERE source_file = %s").format(
                            sql.Identifier("market_structure"),
                            sql.Identifier(job.table),
                        ),
                        (path.name,),
                    )

                row_count = 0
                with cursor.copy(copy_statement) as copy:
                    for row in job.read_rows(path):
                        copy.write_row(row)
                        row_count += 1
                if row_count == 0:
                    raise RuntimeError(f"No data rows found in {path}")

                cursor.execute(
                    """
                    INSERT INTO market_structure.ingestion_file (
                        dataset, source_file, source_sha256, source_bytes, rows_loaded
                    ) VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (dataset, source_file) DO UPDATE SET
                        source_sha256 = EXCLUDED.source_sha256,
                        source_bytes = EXCLUDED.source_bytes,
                        rows_loaded = EXCLUDED.rows_loaded,
                        loaded_at = CURRENT_TIMESTAMP
                    """,
                    (job.dataset, path.name, checksum, path.stat().st_size, row_count),
                )
        loaded_files += 1
        print(f"loaded {job.dataset}: {path.name} ({row_count:,} rows)", flush=True)
    return loaded_files, skipped_files


def none_if_blank(value: str | None) -> str | None:
    if value is None or not value.strip():
        return None
    return value.strip()


def decimal_or_none(value: str | None) -> Decimal | None:
    if value is None or not value.strip() or value.strip() == ".":
        return None
    try:
        return Decimal(value.strip())
    except InvalidOperation:
        return None
