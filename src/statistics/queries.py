from __future__ import annotations


def cluster_moments(table: str, x: str, y: str, where: str) -> str:
    return f"""
        WITH base AS (
            SELECT security_id, ({x})::double precision AS x, ({y})::double precision AS y
            FROM {table}
            WHERE {where}
              AND ({x}) IS NOT NULL
              AND ({y}) IS NOT NULL
        ), ranked AS (
            SELECT
                *,
                rank() OVER (ORDER BY x)
                    + (count(*) OVER (PARTITION BY x) - 1) / 2.0 AS x_rank,
                rank() OVER (ORDER BY y)
                    + (count(*) OVER (PARTITION BY y) - 1) / 2.0 AS y_rank
            FROM base
        )
        SELECT
            security_id,
            count(*)::double precision,
            sum(x), sum(y), sum(x * x), sum(y * y), sum(x * y),
            sum(x_rank), sum(y_rank),
            sum(x_rank * x_rank), sum(y_rank * y_rank), sum(x_rank * y_rank)
        FROM ranked
        GROUP BY security_id
        ORDER BY security_id
    """


def within_rank_moments(table: str, x: str, y: str, where: str) -> str:
    return f"""
        WITH base AS (
            SELECT security_id, ({x})::double precision AS x, ({y})::double precision AS y
            FROM {table}
            WHERE {where}
              AND ({x}) IS NOT NULL
              AND ({y}) IS NOT NULL
        ), ranked AS (
            SELECT
                *,
                rank() OVER (PARTITION BY security_id ORDER BY x)
                    + (count(*) OVER (PARTITION BY security_id, x) - 1) / 2.0
                    AS x_rank,
                rank() OVER (PARTITION BY security_id ORDER BY y)
                    + (count(*) OVER (PARTITION BY security_id, y) - 1) / 2.0
                    AS y_rank
            FROM base
        )
        SELECT
            security_id,
            count(*)::double precision,
            sum(x_rank), sum(y_rank),
            sum(x_rank * x_rank), sum(y_rank * y_rank), sum(x_rank * y_rank)
        FROM ranked
        GROUP BY security_id
        ORDER BY security_id
    """


def period_correlations(table: str, date: str, x: str, y: str, where: str) -> str:
    return f"""
        WITH base AS (
            SELECT
                CASE
                    WHEN {date} < date '2021-01-01' THEN '2018_to_2020'
                    WHEN {date} < date '2024-01-01' THEN '2021_to_2023'
                    ELSE '2024_to_july_2026'
                END AS period,
                ({x})::double precision AS x,
                ({y})::double precision AS y
            FROM {table}
            WHERE {where}
              AND ({x}) IS NOT NULL
              AND ({y}) IS NOT NULL
        ), ranked AS (
            SELECT
                *,
                rank() OVER (PARTITION BY period ORDER BY x)
                    + (count(*) OVER (PARTITION BY period, x) - 1) / 2.0 AS x_rank,
                rank() OVER (PARTITION BY period ORDER BY y)
                    + (count(*) OVER (PARTITION BY period, y) - 1) / 2.0 AS y_rank
            FROM base
        )
        SELECT period, count(*)::bigint, corr(x, y), corr(x_rank, y_rank)
        FROM ranked
        GROUP BY period
        ORDER BY period
    """


def ranked_group_summary(table: str, group: str, value: str, where: str) -> str:
    return f"""
        WITH base AS (
            SELECT
                security_id,
                ({group}) AS group_value,
                ({value})::double precision AS value
            FROM {table}
            WHERE {where}
              AND ({group}) IS NOT NULL
              AND ({value}) IS NOT NULL
        ), ranked AS (
            SELECT
                *,
                rank() OVER (ORDER BY value)
                    + (count(*) OVER (PARTITION BY value) - 1) / 2.0 AS value_rank,
                count(*) OVER (PARTITION BY value) AS tie_count
            FROM base
        )
        SELECT
            group_value::text,
            count(*)::bigint,
            avg(value),
            percentile_cont(0.5) WITHIN GROUP (ORDER BY value),
            stddev_samp(value),
            sum(value_rank),
            sum(tie_count * tie_count - 1)::double precision
        FROM ranked
        GROUP BY group_value
        ORDER BY group_value
    """


def clustered_binary_sums(table: str, group: str, value: str, where: str) -> str:
    return f"""
        SELECT
            security_id,
            ({group})::boolean AS group_value,
            count(*)::bigint,
            sum(({value})::double precision)
        FROM {table}
        WHERE {where}
          AND ({group}) IS NOT NULL
          AND ({value}) IS NOT NULL
        GROUP BY security_id, ({group})::boolean
        ORDER BY security_id, group_value
    """


def simple_correlations(table: str, x: str, y: str, where: str, sample: str) -> str:
    escaped_sample = sample.replace("'", "''")
    return f"""
        WITH base AS (
            SELECT ({x})::double precision AS x, ({y})::double precision AS y
            FROM {table}
            WHERE {where}
              AND ({x}) IS NOT NULL
              AND ({y}) IS NOT NULL
        ), ranked AS (
            SELECT
                *,
                rank() OVER (ORDER BY x)
                    + (count(*) OVER (PARTITION BY x) - 1) / 2.0 AS x_rank,
                rank() OVER (ORDER BY y)
                    + (count(*) OVER (PARTITION BY y) - 1) / 2.0 AS y_rank
            FROM base
        )
        SELECT
            '{escaped_sample}'::text,
            count(*)::bigint,
            corr(x, y),
            corr(x_rank, y_rank)
        FROM ranked
    """
