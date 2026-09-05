WITH observed AS (
    SELECT
        'finra_short_volume'::text AS dataset,
        count(*) AS database_rows,
        min(trade_date) AS earliest_date,
        max(trade_date) AS latest_date
    FROM market_structure.raw_short_volume

    UNION ALL

    SELECT
        'finra_short_interest',
        count(*),
        min(settlement_date),
        max(settlement_date)
    FROM market_structure.raw_short_interest

    UNION ALL

    SELECT
        'sec_ftd',
        count(*),
        min(settlement_date),
        max(settlement_date)
    FROM market_structure.raw_ftd
), manifest AS (
    SELECT
        dataset,
        count(*) AS loaded_files,
        sum(rows_loaded) AS manifest_rows
    FROM market_structure.ingestion_file
    GROUP BY dataset
)
SELECT
    observed.dataset,
    manifest.loaded_files,
    observed.database_rows,
    manifest.manifest_rows,
    observed.database_rows = manifest.manifest_rows AS counts_match,
    observed.earliest_date,
    observed.latest_date
FROM observed
LEFT JOIN manifest USING (dataset)
ORDER BY observed.dataset;
