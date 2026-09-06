-- Coverage, alignment availability, and missing source values.
SELECT
    count(*) AS analysis_rows,
    count(DISTINCT security_id) AS securities,
    min(settlement_date) AS first_settlement_date,
    max(settlement_date) AS last_settlement_date,
    count(*) FILTER (WHERE is_primary_analysis_period) AS primary_period_rows,
    count(*) FILTER (WHERE NOT is_primary_analysis_period) AS partial_period_rows,
    count(*) FILTER (WHERE ftd_quantity_history_percentile_band IS NOT NULL)
        AS rows_with_history_context,
    count(*) FILTER (WHERE prior_14d_short_volume_ratio_avg IS NOT NULL)
        AS rows_with_short_volume_context,
    count(*) FILTER (WHERE aligned_short_interest_settlement_date IS NOT NULL)
        AS rows_with_short_interest_context,
    count(*) FILTER (WHERE reference_price IS NULL) AS missing_price_rows,
    count(*) FILTER (WHERE symbol IS NULL) AS blank_symbol_rows
FROM market_structure.ftd_analysis;

-- Percentiles: p01, p05, p25, median, p75, p95, and p99.
SELECT
    metric,
    count(value) AS observations,
    avg(value) AS mean,
    stddev_samp(value) AS standard_deviation,
    min(value) AS minimum,
    percentile_cont(ARRAY[0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99])
        WITHIN GROUP (ORDER BY value) AS percentiles,
    max(value) AS maximum
FROM (
    SELECT 'fails_quantity' AS metric, fails_quantity::double precision AS value
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'ftd_value', ftd_value::double precision
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'prior_14d_short_volume_ratio_avg', prior_14d_short_volume_ratio_avg
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'days_since_short_interest_settlement',
        days_since_short_interest_settlement::double precision
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
) AS distributions
GROUP BY metric
ORDER BY metric;

-- Largest observations are shown for data-quality review, not case selection.
SELECT
    security_id,
    settlement_date,
    symbol,
    cusip,
    fails_quantity,
    reference_price,
    ftd_value,
    ftd_quantity_history_percentile_band,
    ftd_cohort,
    short_interest_full_sample_percentile,
    days_to_cover,
    prior_14d_short_volume_ratio_avg,
    prior_14d_short_volume_ratio_percentile
FROM market_structure.ftd_analysis
WHERE is_primary_analysis_period
ORDER BY fails_quantity DESC
LIMIT 20;

SELECT
    pg_size_pretty(pg_relation_size('market_structure.ftd_analysis')) AS table_size,
    pg_size_pretty(pg_indexes_size('market_structure.ftd_analysis')) AS index_size,
    pg_size_pretty(pg_total_relation_size('market_structure.ftd_analysis'))
        AS total_size;
