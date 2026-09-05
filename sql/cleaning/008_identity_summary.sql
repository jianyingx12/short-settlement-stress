-- Overall mapping outcomes for each cleaned source.
CREATE OR REPLACE VIEW market_structure.identity_match_summary AS
SELECT
    dataset,
    identity_status,
    mapping_confidence,
    mapping_method,
    count(*) AS rows,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY dataset), 4) AS row_percent
FROM (
    SELECT
        'finra_short_volume'::text AS dataset,
        identity_status,
        mapping_confidence,
        mapping_method
    FROM market_structure.short_volume_daily

    UNION ALL

    SELECT
        'finra_short_interest',
        identity_status,
        mapping_confidence,
        mapping_method
    FROM market_structure.short_interest_observation

    UNION ALL

    SELECT
        'sec_ftd',
        identity_status,
        mapping_confidence,
        mapping_method
    FROM market_structure.ftd_daily
) AS mappings
GROUP BY dataset, identity_status, mapping_confidence, mapping_method;

-- Period splits make it visible when mapping coverage changes over time.
CREATE OR REPLACE VIEW market_structure.identity_match_by_period AS
SELECT
    dataset,
    period,
    identity_status,
    mapping_confidence,
    count(*) AS rows,
    round(
        100.0 * count(*) / sum(count(*)) OVER (PARTITION BY dataset, period),
        4
    ) AS row_percent
FROM (
    SELECT
        'finra_short_volume'::text AS dataset,
        CASE
            WHEN trade_date < DATE '2021-01-01' THEN '2018-2020'
            WHEN trade_date < DATE '2024-01-01' THEN '2021-2023'
            ELSE '2024+'
        END AS period,
        identity_status,
        mapping_confidence
    FROM market_structure.short_volume_daily

    UNION ALL

    SELECT
        'finra_short_interest',
        CASE
            WHEN settlement_date < DATE '2021-01-01' THEN '2018-2020'
            WHEN settlement_date < DATE '2024-01-01' THEN '2021-2023'
            ELSE '2024+'
        END,
        identity_status,
        mapping_confidence
    FROM market_structure.short_interest_observation
) AS period_mappings
GROUP BY dataset, period, identity_status, mapping_confidence;

-- OTC rows are outside the primary Consolidated NMS comparison population.
CREATE OR REPLACE VIEW market_structure.primary_short_interest_identity_summary AS
SELECT
    identity_status,
    mapping_confidence,
    mapping_method,
    count(*) AS rows,
    round(100.0 * count(*) / sum(count(*)) OVER (), 4) AS row_percent
FROM market_structure.short_interest_observation
WHERE primary_population
GROUP BY identity_status, mapping_confidence, mapping_method;
