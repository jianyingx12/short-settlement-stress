-- Store duplicate counts once during the build so reports stay accurate without
-- repeatedly grouping tens of millions of rows.
DROP VIEW IF EXISTS market_structure.cleaning_null_summary;
DROP VIEW IF EXISTS market_structure.cleaning_quality_summary;
DROP TABLE IF EXISTS market_structure.cleaning_duplicate_summary;

CREATE TABLE market_structure.cleaning_duplicate_summary (
    dataset text PRIMARY KEY,
    duplicate_rows bigint NOT NULL CHECK (duplicate_rows >= 0)
);

INSERT INTO market_structure.cleaning_duplicate_summary (dataset, duplicate_rows)
SELECT 'finra_short_volume', coalesce(sum(rows_in_key), 0)::bigint
FROM (
    SELECT count(*) AS rows_in_key
    FROM market_structure.short_volume_daily
    GROUP BY trade_date, symbol_raw, market_raw
    HAVING count(*) > 1
) AS duplicates

UNION ALL

SELECT 'finra_short_interest', coalesce(sum(rows_in_key), 0)::bigint
FROM (
    SELECT count(*) AS rows_in_key
    FROM market_structure.short_interest_observation
    GROUP BY settlement_date, symbol_raw, market_class_raw
    HAVING count(*) > 1
) AS duplicates

UNION ALL

SELECT 'sec_ftd', coalesce(sum(rows_in_key), 0)::bigint
FROM (
    SELECT count(*) AS rows_in_key
    FROM market_structure.ftd_daily
    GROUP BY settlement_date, cusip_normalized
    HAVING count(*) > 1
) AS duplicates;

CREATE OR REPLACE VIEW market_structure.cleaning_quality_summary AS
SELECT
    'finra_short_volume'::text AS dataset,
    (SELECT count(*) FROM market_structure.raw_short_volume) AS raw_rows,
    count(*) AS clean_rows,
    (SELECT count(*) FROM market_structure.raw_short_volume) - count(*) AS excluded_rows,
    count(*) FILTER (WHERE quality_status <> 'VALID') AS flagged_rows,
    (SELECT duplicate_rows
     FROM market_structure.cleaning_duplicate_summary
     WHERE dataset = 'finra_short_volume') AS duplicate_rows,
    0::bigint AS revision_rows,
    count(*) FILTER (WHERE symbol_match_key IS NULL) AS missing_symbol_rows,
    0::bigint AS missing_price_rows,
    count(*) FILTER (
        WHERE quality_status IN (
            'NONPOSITIVE_TOTAL_VOLUME',
            'SHORT_VOLUME_GT_TOTAL',
            'SHORT_EXEMPT_GT_SHORT'
        )
    ) AS invalid_quantity_rows
FROM market_structure.short_volume_daily

UNION ALL

SELECT
    'finra_short_interest',
    (SELECT count(*) FROM market_structure.raw_short_interest),
    count(*),
    (SELECT count(*) FROM market_structure.raw_short_interest) - count(*),
    count(*) FILTER (WHERE quality_status <> 'VALID'),
    (SELECT duplicate_rows
     FROM market_structure.cleaning_duplicate_summary
     WHERE dataset = 'finra_short_interest'),
    count(*) FILTER (WHERE is_revision),
    count(*) FILTER (WHERE symbol_match_key IS NULL),
    0,
    count(*) FILTER (WHERE quality_status = 'INVALID_QUANTITY')
FROM market_structure.short_interest_observation

UNION ALL

SELECT
    'sec_ftd',
    (SELECT count(*) FROM market_structure.raw_ftd),
    count(*),
    (SELECT count(*) FROM market_structure.raw_ftd) - count(*),
    count(*) FILTER (WHERE quality_status <> 'VALID'),
    (SELECT duplicate_rows
     FROM market_structure.cleaning_duplicate_summary
     WHERE dataset = 'sec_ftd'),
    0,
    count(*) FILTER (WHERE symbol_missing),
    count(*) FILTER (WHERE reference_price_missing),
    count(*) FILTER (WHERE quality_status = 'INVALID_QUANTITY')
FROM market_structure.ftd_daily;

CREATE OR REPLACE VIEW market_structure.cleaning_null_summary AS
SELECT
    'finra_short_volume'::text AS dataset,
    field_name,
    null_rows,
    round(100.0 * null_rows / total_rows, 4) AS null_percent
FROM (
    SELECT
        count(*) AS total_rows,
        count(*) FILTER (WHERE symbol_match_key IS NULL) AS symbol,
        count(*) FILTER (WHERE short_volume IS NULL) AS short_volume,
        count(*) FILTER (WHERE short_exempt_volume IS NULL) AS short_exempt_volume,
        count(*) FILTER (WHERE total_volume IS NULL) AS total_volume
    FROM market_structure.short_volume_daily
) AS counts
CROSS JOIN LATERAL (
    VALUES
        ('symbol', counts.symbol),
        ('short_volume', counts.short_volume),
        ('short_exempt_volume', counts.short_exempt_volume),
        ('total_volume', counts.total_volume)
) AS fields(field_name, null_rows)

UNION ALL

SELECT
    'finra_short_interest',
    field_name,
    null_rows,
    round(100.0 * null_rows / total_rows, 4)
FROM (
    SELECT
        count(*) AS total_rows,
        count(*) FILTER (WHERE symbol_match_key IS NULL) AS symbol,
        count(*) FILTER (WHERE current_short_position_quantity IS NULL) AS current_position,
        count(*) FILTER (WHERE previous_short_position_quantity IS NULL) AS previous_position,
        count(*) FILTER (WHERE average_daily_volume_quantity IS NULL) AS average_daily_volume,
        count(*) FILTER (WHERE days_to_cover_quantity IS NULL) AS days_to_cover,
        count(*) FILTER (WHERE publication_date IS NULL) AS publication_date
    FROM market_structure.short_interest_observation
) AS counts
CROSS JOIN LATERAL (
    VALUES
        ('symbol', counts.symbol),
        ('current_short_position', counts.current_position),
        ('previous_short_position', counts.previous_position),
        ('average_daily_volume', counts.average_daily_volume),
        ('days_to_cover', counts.days_to_cover),
        ('publication_date', counts.publication_date)
) AS fields(field_name, null_rows)

UNION ALL

SELECT
    'sec_ftd',
    field_name,
    null_rows,
    round(100.0 * null_rows / total_rows, 4)
FROM (
    SELECT
        count(*) AS total_rows,
        count(*) FILTER (WHERE symbol_match_key IS NULL) AS symbol,
        count(*) FILTER (WHERE cusip_normalized IS NULL) AS cusip,
        count(*) FILTER (
            WHERE issuer_name_raw IS NULL OR btrim(issuer_name_raw) = ''
        ) AS issuer_name,
        count(*) FILTER (WHERE reference_price IS NULL) AS reference_price
    FROM market_structure.ftd_daily
) AS counts
CROSS JOIN LATERAL (
    VALUES
        ('symbol', counts.symbol),
        ('cusip', counts.cusip),
        ('issuer_name', counts.issuer_name),
        ('reference_price', counts.reference_price)
) AS fields(field_name, null_rows);
