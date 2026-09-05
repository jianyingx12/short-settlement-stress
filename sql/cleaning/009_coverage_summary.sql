CREATE OR REPLACE VIEW market_structure.cleaning_coverage_summary AS
SELECT
    'finra_short_volume'::text AS dataset,
    min(trade_date) AS earliest_date,
    max(trade_date) AS latest_date,
    count(*) AS clean_rows,
    count(DISTINCT symbol_raw) AS source_symbols,
    count(DISTINCT security_id) AS matched_security_ids
FROM market_structure.short_volume_daily

UNION ALL

SELECT
    'finra_short_interest',
    min(settlement_date),
    max(settlement_date),
    count(*),
    count(DISTINCT symbol_raw),
    count(DISTINCT security_id)
FROM market_structure.short_interest_observation

UNION ALL

SELECT
    'sec_ftd',
    min(settlement_date),
    max(settlement_date),
    count(*),
    count(DISTINCT symbol_raw),
    count(DISTINCT security_id)
FROM market_structure.ftd_daily;

CREATE OR REPLACE VIEW market_structure.security_dataset_overlap AS
WITH presence AS (
    SELECT security_id, 'short_volume' AS dataset
    FROM market_structure.short_volume_daily
    WHERE security_id IS NOT NULL
    GROUP BY security_id

    UNION ALL

    SELECT security_id, 'short_interest'
    FROM market_structure.short_interest_observation
    WHERE security_id IS NOT NULL
    GROUP BY security_id

    UNION ALL

    SELECT security_id, 'ftd'
    FROM market_structure.ftd_daily
    WHERE security_id IS NOT NULL
    GROUP BY security_id
), dataset_counts AS (
    SELECT security_id, count(*) AS dataset_count
    FROM presence
    GROUP BY security_id
)
SELECT dataset_count, count(*) AS security_count
FROM dataset_counts
GROUP BY dataset_count;

CREATE OR REPLACE VIEW market_structure.high_confidence_security_overlap AS
WITH presence AS (
    SELECT security_id, 'short_volume' AS dataset
    FROM market_structure.short_volume_daily
    WHERE mapping_confidence = 'HIGH'
    GROUP BY security_id

    UNION ALL

    SELECT security_id, 'short_interest'
    FROM market_structure.short_interest_observation
    WHERE mapping_confidence = 'HIGH'
      AND primary_population
    GROUP BY security_id

    UNION ALL

    SELECT security_id, 'ftd'
    FROM market_structure.ftd_daily
    WHERE mapping_confidence = 'HIGH'
    GROUP BY security_id
), dataset_counts AS (
    SELECT security_id, count(*) AS dataset_count
    FROM presence
    GROUP BY security_id
)
SELECT dataset_count, count(*) AS security_count
FROM dataset_counts
GROUP BY dataset_count;

-- A short-volume month is complete only after a later source month exists.
-- Short interest needs both cycles, and SEC FTD needs the second-half archive.
CREATE OR REPLACE VIEW market_structure.latest_complete_shared_month AS
WITH short_volume_months AS (
    SELECT date_trunc('month', trade_date)::date AS month
    FROM market_structure.short_volume_daily
    GROUP BY date_trunc('month', trade_date)::date
    HAVING date_trunc('month', max(trade_date)) < (
        SELECT date_trunc('month', max(latest.trade_date))
        FROM market_structure.short_volume_daily AS latest
    )
), short_interest_months AS (
    SELECT date_trunc('month', settlement_date)::date AS month
    FROM market_structure.short_interest_observation
    GROUP BY date_trunc('month', settlement_date)::date
    HAVING count(DISTINCT settlement_date) >= 2
), complete_ftd_months AS (
    SELECT make_date(
        substring(source_file FROM 9 FOR 4)::integer,
        substring(source_file FROM 13 FOR 2)::integer,
        1
    ) AS month
    FROM market_structure.ingestion_file
    WHERE dataset = 'sec_ftd'
      AND source_file ~ '^cnsfails[0-9]{6}b[.]zip$'
)
SELECT max(short_volume.month) AS latest_complete_shared_month
FROM short_volume_months AS short_volume
JOIN short_interest_months AS short_interest USING (month)
JOIN complete_ftd_months AS ftd USING (month);
