WITH observed AS (
    SELECT
        'finra_short_volume'::text AS dataset,
        count(*) AS row_count,
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
), expected(dataset, row_count, earliest_date, latest_date) AS (
    VALUES
        ('finra_short_volume', 19473114::bigint, DATE '2018-08-01', DATE '2026-09-04'),
        ('finra_short_interest', 3693310::bigint, DATE '2018-08-15', DATE '2026-08-14'),
        ('sec_ftd', 10465644::bigint, DATE '2018-08-01', DATE '2026-08-14')
)
SELECT
    observed.dataset,
    observed.row_count,
    expected.row_count AS expected_rows,
    observed.earliest_date,
    observed.latest_date,
    (observed.row_count = expected.row_count
        AND observed.earliest_date = expected.earliest_date
        AND observed.latest_date = expected.latest_date) AS matches_phase_1
FROM observed
JOIN expected USING (dataset)
ORDER BY observed.dataset;
