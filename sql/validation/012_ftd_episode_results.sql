-- Main comparison between isolated and persistent episodes.
SELECT
    episode_class,
    count(*) AS episodes,
    count(DISTINCT security_id) AS securities,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY observation_count)
        AS median_observation_count,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_calendar_days)
        AS median_calendar_days,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY max_fails_quantity)
        AS median_peak_quantity,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY peak_ftd_history_percentile_band
    ) AS median_peak_history_band,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY ftd_balance_days)
        AS median_balance_days,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY short_interest_full_sample_percentile
    ) AS median_short_interest_percentile,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_cover)
        AS median_days_to_cover,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_percentile
    ) AS median_prior_short_volume_percentile,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_trend
    ) AS median_prior_short_volume_trend
FROM market_structure.ftd_episodes
WHERE is_primary_analysis_period
  AND NOT is_left_censored
GROUP BY episode_class
ORDER BY episode_class;

-- Overall distribution of episode length and severity.
SELECT
    percentile_cont(ARRAY[0.25, 0.5, 0.75, 0.9, 0.99])
        WITHIN GROUP (ORDER BY observation_count) AS observation_count_quantiles,
    percentile_cont(ARRAY[0.25, 0.5, 0.75, 0.9, 0.99])
        WITHIN GROUP (ORDER BY duration_calendar_days) AS calendar_day_quantiles,
    percentile_cont(ARRAY[0.25, 0.5, 0.75, 0.9, 0.99])
        WITHIN GROUP (ORDER BY max_fails_quantity) AS peak_quantity_quantiles,
    percentile_cont(ARRAY[0.25, 0.5, 0.75, 0.9, 0.99])
        WITHIN GROUP (ORDER BY ftd_balance_days) AS balance_day_quantiles
FROM market_structure.ftd_episodes
WHERE is_primary_analysis_period
  AND NOT is_left_censored;

SELECT
    intensity_group,
    count(*) AS episodes,
    count(*)::double precision / sum(count(*)) OVER () AS share
FROM market_structure.ftd_episodes
WHERE is_primary_analysis_period
  AND NOT is_left_censored
GROUP BY intensity_group
ORDER BY episodes DESC;

SELECT
    duration_group,
    count(*) AS episodes,
    count(*)::double precision / sum(count(*)) OVER () AS share,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY max_fails_quantity)
        AS median_peak_quantity,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY peak_ftd_history_percentile_band
    ) AS median_peak_history_band,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY short_interest_full_sample_percentile
    ) AS median_short_interest_percentile,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_percentile
    ) AS median_prior_short_volume_percentile
FROM market_structure.ftd_episodes
WHERE is_primary_analysis_period
  AND NOT is_left_censored
GROUP BY duration_group
ORDER BY min(CASE duration_group
    WHEN '1_observation' THEN 1
    WHEN '2_to_3' THEN 2
    WHEN '4_to_5' THEN 4
    WHEN '6_to_10' THEN 6
    ELSE 11
END);

-- Duration and peak severity are separate episode properties.
WITH values AS (
    SELECT
        observation_count::double precision AS duration,
        peak_ftd_history_percentile_band AS severity
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
      AND NOT is_left_censored
      AND peak_ftd_history_percentile_band IS NOT NULL
), ranked AS (
    SELECT
        duration,
        severity,
        rank() OVER (ORDER BY duration)
            + (count(*) OVER (PARTITION BY duration) - 1) / 2.0 AS duration_rank,
        rank() OVER (ORDER BY severity)
            + (count(*) OVER (PARTITION BY severity) - 1) / 2.0 AS severity_rank
    FROM values
)
SELECT
    count(*) AS observations,
    corr(duration, severity) AS pearson_correlation,
    corr(duration_rank, severity_rank) AS spearman_correlation
FROM ranked;

SELECT
    persistent_regime,
    count(*) AS episodes,
    count(*)::double precision / sum(count(*)) OVER () AS share
FROM market_structure.ftd_episodes
WHERE is_primary_analysis_period
  AND NOT is_left_censored
  AND persistent_regime IS NOT NULL
GROUP BY persistent_regime
ORDER BY episodes DESC;

-- Recurrence is measured without merging separated episodes.
WITH securities AS (
    SELECT
        security_id,
        count(*) AS episode_count,
        count(*)::double precision
            / greatest(
                (max(episode_end_date) - min(episode_start_date) + 1) / 365.25,
                1.0
            ) AS episodes_per_observed_year
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
    GROUP BY security_id
), gaps AS (
    SELECT days_since_previous_episode
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
      AND days_since_previous_episode IS NOT NULL
)
SELECT
    count(*) AS securities,
    avg(episode_count) AS mean_episodes_per_security,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY episode_count)
        AS median_episodes_per_security,
    max(episode_count) AS maximum_episodes,
    (SELECT percentile_cont(0.5) WITHIN GROUP (
        ORDER BY days_since_previous_episode
    ) FROM gaps) AS median_days_between_episodes,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY episodes_per_observed_year)
        AS median_episodes_per_observed_year
FROM securities;
