CREATE TABLE market_structure.bi_ftd_episode_distribution AS
WITH counts AS (
    SELECT
        duration_group,
        count(*)::bigint AS episode_count
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
      AND NOT is_left_censored
    GROUP BY duration_group
)
SELECT
    duration_group,
    CASE duration_group
        WHEN '1_observation' THEN '1 observation'
        WHEN '2_to_3' THEN '2 to 3'
        WHEN '4_to_5' THEN '4 to 5'
        WHEN '6_to_10' THEN '6 to 10'
        WHEN '11_plus' THEN '11 and above'
    END AS duration_label,
    CASE duration_group
        WHEN '1_observation' THEN 1
        WHEN '2_to_3' THEN 2
        WHEN '4_to_5' THEN 3
        WHEN '6_to_10' THEN 4
        WHEN '11_plus' THEN 5
    END AS duration_order,
    episode_count,
    episode_count::double precision / sum(episode_count) OVER () AS episode_share
FROM counts;

ALTER TABLE market_structure.bi_ftd_episode_distribution
    ADD PRIMARY KEY (duration_group);

CREATE TABLE market_structure.bi_ftd_episode_comparison AS
WITH values AS (
    SELECT
        episode.episode_class,
        metric.metric,
        metric.metric_label,
        metric.metric_order,
        metric.value
    FROM market_structure.ftd_episodes AS episode
    CROSS JOIN LATERAL (VALUES
        ('peak_ftd_quantity', 'Peak FTD quantity', 1,
            episode.max_fails_quantity::double precision),
        ('peak_ftd_intensity', 'Peak historical FTD intensity', 2,
            episode.peak_ftd_history_percentile_band::double precision),
        ('prior_short_activity', 'Prior short activity percentile', 3,
            episode.prior_14d_short_volume_ratio_percentile::double precision),
        ('short_interest', 'Short-interest percentile', 4,
            episode.short_interest_full_sample_percentile::double precision)
    ) AS metric(metric, metric_label, metric_order, value)
    WHERE episode.is_primary_analysis_period
      AND NOT episode.is_left_censored
      AND metric.value IS NOT NULL
)
SELECT
    episode_class,
    CASE episode_class WHEN 'isolated' THEN 'Isolated' ELSE 'Persistent' END
        AS episode_class_label,
    metric,
    metric_label,
    metric_order,
    count(*)::bigint AS episode_count,
    avg(value) AS mean_value,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY value) AS median_value
FROM values
GROUP BY episode_class, metric, metric_label, metric_order;

ALTER TABLE market_structure.bi_ftd_episode_comparison
    ADD PRIMARY KEY (episode_class, metric);

CREATE TABLE market_structure.bi_ftd_duration_severity AS
SELECT
    duration_group,
    CASE duration_group
        WHEN '1_observation' THEN '1 observation'
        WHEN '2_to_3' THEN '2 to 3'
        WHEN '4_to_5' THEN '4 to 5'
        WHEN '6_to_10' THEN '6 to 10'
        WHEN '11_plus' THEN '11 and above'
    END AS duration_label,
    CASE duration_group
        WHEN '1_observation' THEN 1
        WHEN '2_to_3' THEN 2
        WHEN '4_to_5' THEN 3
        WHEN '6_to_10' THEN 4
        WHEN '11_plus' THEN 5
    END AS duration_order,
    count(*)::bigint AS episode_count,
    avg(observation_count)::double precision AS mean_observation_count,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY peak_ftd_history_percentile_band
    ) AS median_peak_ftd_intensity,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY max_fails_quantity
    ) AS median_peak_ftd_quantity
FROM market_structure.ftd_episodes
WHERE is_primary_analysis_period
  AND NOT is_left_censored
  AND peak_ftd_history_percentile_band IS NOT NULL
GROUP BY duration_group;

ALTER TABLE market_structure.bi_ftd_duration_severity
    ADD PRIMARY KEY (duration_group);

CREATE TABLE market_structure.bi_ftd_recurrence AS
WITH security_counts AS (
    SELECT security_id, count(*)::integer AS episode_count
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
      AND NOT is_left_censored
    GROUP BY security_id
), grouped AS (
    SELECT
        CASE
            WHEN episode_count = 1 THEN '1_episode'
            WHEN episode_count = 2 THEN '2_episodes'
            WHEN episode_count <= 5 THEN '3_to_5'
            WHEN episode_count <= 10 THEN '6_to_10'
            ELSE '11_plus'
        END AS recurrence_group,
        count(*)::bigint AS security_count
    FROM security_counts
    GROUP BY 1
)
SELECT
    recurrence_group,
    CASE recurrence_group
        WHEN '1_episode' THEN '1 episode'
        WHEN '2_episodes' THEN '2 episodes'
        WHEN '3_to_5' THEN '3 to 5'
        WHEN '6_to_10' THEN '6 to 10'
        WHEN '11_plus' THEN '11 and above'
    END AS recurrence_label,
    CASE recurrence_group
        WHEN '1_episode' THEN 1
        WHEN '2_episodes' THEN 2
        WHEN '3_to_5' THEN 3
        WHEN '6_to_10' THEN 4
        WHEN '11_plus' THEN 5
    END AS recurrence_order,
    security_count,
    security_count::double precision / sum(security_count) OVER () AS security_share
FROM grouped;

ALTER TABLE market_structure.bi_ftd_recurrence
    ADD PRIMARY KEY (recurrence_group);

-- This is the four-way p99 context split used on the relationship page.
CREATE TABLE market_structure.bi_ftd_regime_summary AS
WITH counts AS (
    SELECT extreme_ftd_regime AS regime, count(*)::bigint AS observation_count
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
      AND extreme_ftd_regime IS NOT NULL
    GROUP BY extreme_ftd_regime
)
SELECT
    regime,
    CASE regime
        WHEN 'high_ftd_lower_si_normal_activity' THEN 'Lower SI / normal activity'
        WHEN 'high_ftd_high_si_normal_activity' THEN 'High SI / normal activity'
        WHEN 'high_ftd_lower_si_high_activity' THEN 'Lower SI / high activity'
        WHEN 'high_ftd_high_si_high_activity' THEN 'High SI / high activity'
    END AS regime_label,
    CASE regime
        WHEN 'high_ftd_lower_si_normal_activity' THEN 1
        WHEN 'high_ftd_high_si_normal_activity' THEN 2
        WHEN 'high_ftd_lower_si_high_activity' THEN 3
        WHEN 'high_ftd_high_si_high_activity' THEN 4
    END AS regime_order,
    observation_count,
    observation_count::double precision / sum(observation_count) OVER ()
        AS observation_share
FROM counts;

ALTER TABLE market_structure.bi_ftd_regime_summary
    ADD PRIMARY KEY (regime);

COMMENT ON TABLE market_structure.bi_ftd_episode_comparison IS
    'Small import table comparing isolated and persistent episode medians.';

COMMENT ON TABLE market_structure.bi_ftd_regime_summary IS
    'Four-way short-interest and short-activity context for p99 FTD observations.';
