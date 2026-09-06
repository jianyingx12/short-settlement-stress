-- These correlations describe the sample; they do not test significance.
WITH pair_values AS (
    SELECT pairs.pair, pairs.x, pairs.y
    FROM market_structure.short_interest_cycles AS cycle
    CROSS JOIN LATERAL (VALUES
        ('rq1_volume_average_vs_si_percentile',
            cycle.prior_14d_short_volume_ratio_avg,
            cycle.short_interest_full_sample_percentile),
        ('rq1_volume_percentile_vs_si_percentile',
            cycle.prior_14d_short_volume_ratio_percentile,
            cycle.short_interest_full_sample_percentile),
        ('rq1_volume_average_vs_days_to_cover',
            cycle.prior_14d_short_volume_ratio_avg,
            cycle.days_to_cover),
        ('rq2_activity_change_vs_log_si_change',
            cycle.prior_14d_short_volume_ratio_avg_change,
            cycle.signed_log_short_interest_change),
        ('rq2_volume_level_vs_log_si_change',
            cycle.prior_14d_short_volume_ratio_percentile,
            cycle.signed_log_short_interest_change),
        ('rq2_volume_level_vs_absolute_si_change',
            cycle.prior_14d_short_volume_ratio_percentile,
            cycle.absolute_short_interest_change::double precision),
        ('rq2_volume_level_vs_percentage_si_change',
            cycle.prior_14d_short_volume_ratio_percentile,
            cycle.percentage_short_interest_change),
        ('rq2_volume_level_vs_days_to_cover_change',
            cycle.prior_14d_short_volume_ratio_percentile,
            cycle.days_to_cover_change)
    ) AS pairs(pair, x, y)
    WHERE cycle.is_primary_analysis_period
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

-- Short interest by recent short-volume activity.
SELECT
    short_volume_cohort,
    count(*) AS observations,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY short_interest_full_sample_percentile
    ) AS median_short_interest_percentile,
    avg(short_interest_full_sample_percentile) AS mean_short_interest_percentile,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_cover)
        AS median_days_to_cover,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY absolute_short_interest_change
    ) AS median_absolute_short_interest_change,
    avg(absolute_short_interest_change) AS mean_absolute_short_interest_change
FROM market_structure.short_interest_cycles
WHERE is_primary_analysis_period
  AND short_volume_cohort IS NOT NULL
GROUP BY short_volume_cohort
ORDER BY min(prior_14d_short_volume_ratio_percentile);

-- Short-interest changes by change in short-volume activity.
SELECT
    activity_change_cohort,
    count(*) AS observations,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY signed_log_short_interest_change
    ) AS median_signed_log_change,
    avg(signed_log_short_interest_change) AS mean_signed_log_change,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY absolute_short_interest_change
    ) AS median_absolute_change,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY percentage_short_interest_change
    ) AS median_percentage_change,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_cover_change)
        AS median_days_to_cover_change
FROM market_structure.short_interest_cycles
WHERE is_primary_analysis_period
  AND activity_change_cohort IS NOT NULL
GROUP BY activity_change_cohort
ORDER BY min(prior_14d_activity_change_percentile);
