-- Pooled correlations are descriptive; relative measures use fixed prior baselines.
WITH pair_values AS (
    SELECT pairs.pair, pairs.x, pairs.y
    FROM market_structure.ftd_analysis AS ftd
    CROSS JOIN LATERAL (VALUES
        ('relative_ftd_vs_short_interest',
            ftd.ftd_quantity_history_percentile_band,
            ftd.short_interest_full_sample_percentile),
        ('relative_ftd_vs_short_activity',
            ftd.ftd_quantity_history_percentile_band,
            ftd.prior_14d_short_volume_ratio_percentile),
        ('absolute_ftd_vs_short_interest',
            ftd.fails_quantity::double precision,
            ftd.short_interest_full_sample_percentile),
        ('absolute_ftd_vs_short_activity',
            ftd.fails_quantity::double precision,
            ftd.prior_14d_short_volume_ratio_percentile)
    ) AS pairs(pair, x, y)
    WHERE ftd.is_primary_analysis_period
      AND pairs.x IS NOT NULL
      AND pairs.y IS NOT NULL
), ranked AS (
    SELECT
        pair,
        x,
        y,
        rank() OVER (PARTITION BY pair ORDER BY x)
            + (count(*) OVER (PARTITION BY pair, x) - 1) / 2.0 AS x_rank,
        rank() OVER (PARTITION BY pair ORDER BY y)
            + (count(*) OVER (PARTITION BY pair, y) - 1) / 2.0 AS y_rank
    FROM pair_values
)
SELECT
    pair,
    count(*) AS observations,
    corr(x, y) AS pearson_correlation,
    corr(x_rank, y_rank) AS spearman_correlation
FROM ranked
GROUP BY pair
ORDER BY pair;

-- Short-interest and short-volume context by predetermined FTD cohort.
SELECT
    ftd_cohort,
    count(*) AS observations,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY short_interest_full_sample_percentile
    ) AS median_short_interest_percentile,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_cover)
        AS median_days_to_cover,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY signed_log_short_interest_change
    ) AS median_signed_log_short_interest_change,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_avg
    ) AS median_prior_14d_short_volume_ratio,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_percentile
    ) AS median_short_volume_percentile,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_trend
    ) AS median_short_volume_trend
FROM market_structure.ftd_analysis
WHERE is_primary_analysis_period
GROUP BY ftd_cohort
ORDER BY min(CASE ftd_cohort
    WHEN 'insufficient_history' THEN 0
    WHEN 'below_p95' THEN 1
    WHEN 'p95_to_p99' THEN 2
    WHEN 'p99_to_p995' THEN 3
    WHEN 'p995_plus' THEN 4
END);

SELECT
    extreme_ftd_regime,
    count(*) AS observations,
    count(*)::double precision / sum(count(*)) OVER () AS share
FROM market_structure.ftd_analysis
WHERE is_primary_analysis_period
  AND extreme_ftd_regime IS NOT NULL
GROUP BY extreme_ftd_regime
ORDER BY observations DESC;
