from __future__ import annotations

import argparse
from pathlib import Path

from src.ingestion.common import DEFAULT_RAW_ROOT
from . import finra_short_interest, finra_short_volume, sec_ftd
from .common import LoadJob, load_dataset, read_database_settings


def get_load_jobs(raw_root: Path) -> tuple[LoadJob, ...]:
    return (
        LoadJob(
            "finra_short_volume",
            "raw_short_volume",
            finra_short_volume.COPY_COLUMNS,
            finra_short_volume.files(raw_root),
            finra_short_volume.rows,
        ),
        LoadJob(
            "finra_short_interest",
            "raw_short_interest",
            finra_short_interest.COPY_COLUMNS,
            finra_short_interest.files(raw_root),
            finra_short_interest.rows,
        ),
        LoadJob(
            "sec_ftd",
            "raw_ftd",
            sec_ftd.COPY_COLUMNS,
            sec_ftd.files(raw_root),
            sec_ftd.rows,
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Load the existing raw source files into PostgreSQL with COPY."
    )
    parser.add_argument("--raw-root", type=Path, default=DEFAULT_RAW_ROOT)
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    parser.add_argument(
        "--dataset",
        choices=("finra_short_volume", "finra_short_interest", "sec_ftd"),
        action="append",
        help="Load one dataset; repeat the option to select more than one.",
    )
    args = parser.parse_args()

    database_settings = read_database_settings(args.env_file)
    selected = set(args.dataset or ())
    jobs = [
        job
        for job in get_load_jobs(args.raw_root)
        if not selected or job.dataset in selected
    ]
    empty = [job.dataset for job in jobs if not job.files]
    if empty:
        parser.error(f"no raw files found for: {', '.join(empty)}")

    try:
        import psycopg
    except ImportError as exc:
        raise RuntimeError("Install database dependencies with: pip install -r requirements.txt") from exc

    with psycopg.connect(**database_settings, autocommit=True) as connection:
        for job in jobs:
            loaded, skipped = load_dataset(connection, job)
            print(f"{job.dataset}: {loaded} loaded, {skipped} unchanged", flush=True)


if __name__ == "__main__":
    main()
