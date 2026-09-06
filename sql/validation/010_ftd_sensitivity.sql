-- Compare the fixed 95th, 99th, and 99.5th percentile thresholds.
WITH thresholds AS (
    SELECT
        'p95' AS threshold,
        exceeds_baseline_p95 AS is_extreme,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_percentile
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'p99', exceeds_baseline_p99,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_percentile
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT 'p995', exceeds_baseline_p995,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_percentile
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
)
SELECT
    threshold,
    count(*) FILTER (WHERE is_extreme) AS extreme_observations,
    avg(short_interest_full_sample_percentile) FILTER (WHERE is_extreme)
        AS mean_short_interest_percentile,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY short_interest_full_sample_percentile
    ) FILTER (WHERE is_extreme) AS median_short_interest_percentile,
    avg(prior_14d_short_volume_ratio_percentile) FILTER (WHERE is_extreme)
        AS mean_short_volume_percentile,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_percentile
    ) FILTER (WHERE is_extreme) AS median_short_volume_percentile
FROM thresholds
WHERE is_extreme IS NOT NULL
GROUP BY threshold
ORDER BY min(CASE threshold WHEN 'p95' THEN 95 WHEN 'p99' THEN 99 ELSE 995 END);

-- Compare the market-wide top 1% by quantity with each security's historical p99.
WITH cutoff AS (
    SELECT percentile_cont(0.99) WITHIN GROUP (ORDER BY fails_quantity)
        AS absolute_p99
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
), classified AS (
    SELECT
        fails_quantity >= cutoff.absolute_p99 AS is_absolute_p99,
        exceeds_baseline_p99
    FROM market_structure.ftd_analysis
    CROSS JOIN cutoff
    WHERE is_primary_analysis_period
      AND exceeds_baseline_p99 IS NOT NULL
)
SELECT
    count(*) FILTER (WHERE is_absolute_p99) AS absolute_p99_rows,
    count(*) FILTER (WHERE exceeds_baseline_p99) AS historical_p99_rows,
    count(*) FILTER (WHERE is_absolute_p99 AND exceeds_baseline_p99) AS overlap_rows,
    count(*) FILTER (WHERE is_absolute_p99 AND exceeds_baseline_p99)::double precision
        / nullif(count(*) FILTER (WHERE is_absolute_p99), 0)
        AS absolute_rows_also_historically_extreme,
    count(*) FILTER (WHERE is_absolute_p99 AND exceeds_baseline_p99)::double precision
        / nullif(count(*) FILTER (WHERE exceeds_baseline_p99), 0)
        AS historical_rows_also_absolutely_large
FROM classified;

-- Missing prices remain in quantity summaries.
SELECT
    reference_price IS NULL AS reference_price_missing,
    count(*) AS observations,
    avg(fails_quantity::double precision) AS mean_fails_quantity,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY fails_quantity)
        AS median_fails_quantity,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY fails_quantity)
        AS p95_fails_quantity
FROM market_structure.ftd_analysis
WHERE is_primary_analysis_period
GROUP BY reference_price IS NULL
ORDER BY reference_price IS NULL;

-- Require high-confidence mappings from FTD, short volume, and short interest.
WITH samples AS (
    SELECT
        'high_and_medium_context' AS sample,
        ftd_quantity_history_percentile_band,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_percentile
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT
        'high_only_context',
        ftd_quantity_history_percentile_band,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_percentile
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
      AND ftd_mapping_confidence = 'HIGH'
      AND short_volume_mapping_confidence = 'HIGH'
      AND short_interest_mapping_confidence = 'HIGH'
)
SELECT
    sample,
    count(*) FILTER (
        WHERE ftd_quantity_history_percentile_band IS NOT NULL
          AND short_interest_full_sample_percentile IS NOT NULL
    ) AS short_interest_observations,
    corr(
        ftd_quantity_history_percentile_band,
        short_interest_full_sample_percentile
    ) AS short_interest_correlation,
    count(*) FILTER (
        WHERE ftd_quantity_history_percentile_band IS NOT NULL
          AND prior_14d_short_volume_ratio_percentile IS NOT NULL
    ) AS short_volume_observations,
    corr(
        ftd_quantity_history_percentile_band,
        prior_14d_short_volume_ratio_percentile
    ) AS short_volume_correlation
FROM samples
GROUP BY sample
ORDER BY sample;

SELECT
    count(days_since_short_interest_settlement) AS observations,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY days_since_short_interest_settlement
    ) AS median_days,
    percentile_cont(0.9) WITHIN GROUP (
        ORDER BY days_since_short_interest_settlement
    ) AS p90_days,
    max(days_since_short_interest_settlement) AS maximum_days
FROM market_structure.ftd_analysis
WHERE is_primary_analysis_period;
