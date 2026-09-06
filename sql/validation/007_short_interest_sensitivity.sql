-- Check whether extreme values are concentrated in low-volume rows.
WITH volume_deciles AS (
    SELECT
        prior_14d_total_volume_avg,
        prior_14d_short_volume_ratio_percentile,
        prior_trade_date_history_zscore,
        ntile(10) OVER (ORDER BY prior_14d_total_volume_avg) AS volume_decile
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
      AND prior_14d_total_volume_avg IS NOT NULL
)
SELECT
    volume_decile,
    count(*) AS observations,
    min(prior_14d_total_volume_avg) AS minimum_average_volume,
    max(prior_14d_total_volume_avg) AS maximum_average_volume,
    count(*) FILTER (WHERE prior_14d_short_volume_ratio_percentile >= 0.90)
        AS top_activity_rows,
    count(*) FILTER (WHERE abs(prior_trade_date_history_zscore) > 10)
        AS absolute_zscore_above_10
FROM volume_deciles
GROUP BY volume_decile
ORDER BY volume_decile;

-- Compare the main correlations using stricter identity and revision samples.
WITH samples AS (
    SELECT
        'high_and_medium' AS sample,
        prior_14d_short_volume_ratio_percentile,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_avg_change,
        signed_log_short_interest_change
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
    UNION ALL
    SELECT
        'high_only',
        prior_14d_short_volume_ratio_percentile,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_avg_change,
        signed_log_short_interest_change
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
      AND short_interest_mapping_confidence = 'HIGH'
      AND prior_14d_all_high_confidence
    UNION ALL
    SELECT
        'excluding_revisions',
        prior_14d_short_volume_ratio_percentile,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_avg_change,
        signed_log_short_interest_change
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
      AND NOT is_revision
)
SELECT
    sample,
    count(*) FILTER (
        WHERE prior_14d_short_volume_ratio_percentile IS NOT NULL
          AND short_interest_full_sample_percentile IS NOT NULL
    ) AS rq1_observations,
    corr(
        prior_14d_short_volume_ratio_percentile,
        short_interest_full_sample_percentile
    ) AS rq1_percentile_correlation,
    count(*) FILTER (
        WHERE prior_14d_short_volume_ratio_avg_change IS NOT NULL
          AND signed_log_short_interest_change IS NOT NULL
    ) AS rq2_observations,
    corr(
        prior_14d_short_volume_ratio_avg_change,
        signed_log_short_interest_change
    ) AS rq2_change_correlation
FROM samples
GROUP BY sample
ORDER BY sample;
