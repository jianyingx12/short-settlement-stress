-- Cycle coverage and known data issues.
SELECT
    count(*) AS cycle_rows,
    count(DISTINCT security_id) AS securities,
    min(settlement_date) AS first_settlement_date,
    max(settlement_date) AS last_settlement_date,
    count(*) FILTER (WHERE is_primary_analysis_period) AS primary_period_rows,
    count(*) FILTER (WHERE NOT is_primary_analysis_period) AS partial_period_rows,
    count(*) FILTER (WHERE short_interest_mapping_confidence = 'HIGH')
        AS high_confidence_rows,
    count(*) FILTER (WHERE short_interest_mapping_confidence = 'MEDIUM')
        AS medium_confidence_rows,
    count(*) FILTER (WHERE prior_14d_observation_count = 14)
        AS complete_prior_14d_rows,
    count(*) FILTER (WHERE is_revision) AS revision_rows,
    count(*) FILTER (WHERE has_stock_split) AS stock_split_rows,
    count(*) FILTER (WHERE reported_previous_matches_cycle = false)
        AS reported_previous_disagreements
FROM market_structure.short_interest_cycles;

SELECT count(*) AS eligible_rows_without_publication_date
FROM market_structure.short_interest_observation
WHERE primary_population
  AND quality_status = 'VALID'
  AND identity_status = 'MATCHED'
  AND mapping_confidence IN ('HIGH', 'MEDIUM')
  AND security_id IS NOT NULL
  AND publication_date IS NULL;

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
    SELECT 'absolute_short_interest_change' AS metric,
        absolute_short_interest_change::double precision AS value
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'percentage_short_interest_change', percentage_short_interest_change
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'days_to_cover_change', days_to_cover_change
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'prior_14d_short_volume_ratio_avg', prior_14d_short_volume_ratio_avg
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
) AS distributions
GROUP BY metric
ORDER BY metric;

-- Largest percentage changes, with the prior position shown for context.
SELECT
    security_id,
    settlement_date,
    symbol,
    previous_cycle_short_position,
    current_short_position,
    absolute_short_interest_change,
    percentage_short_interest_change,
    has_stock_split,
    is_revision
FROM market_structure.short_interest_cycles
WHERE is_primary_analysis_period
  AND percentage_short_interest_change IS NOT NULL
ORDER BY abs(percentage_short_interest_change) DESC
LIMIT 20;

SELECT
    pg_size_pretty(pg_relation_size('market_structure.short_interest_cycles'))
        AS table_size,
    pg_size_pretty(pg_indexes_size('market_structure.short_interest_cycles'))
        AS index_size,
    pg_size_pretty(pg_total_relation_size('market_structure.short_interest_cycles'))
        AS total_size;
