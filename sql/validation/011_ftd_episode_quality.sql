-- Episode coverage and context availability.
SELECT
    count(*) AS episodes,
    count(DISTINCT security_id) AS securities,
    min(episode_start_date) AS first_episode_start,
    max(episode_end_date) AS last_episode_end,
    sum(observation_count) AS represented_ftd_observations,
    count(*) FILTER (WHERE is_primary_analysis_period) AS primary_episodes,
    count(*) FILTER (WHERE peak_ftd_history_percentile_band IS NOT NULL)
        AS episodes_with_history_context,
    count(*) FILTER (WHERE prior_14d_short_volume_ratio_avg IS NOT NULL)
        AS episodes_with_short_volume_context,
    count(*) FILTER (WHERE aligned_short_interest_settlement_date IS NOT NULL)
        AS episodes_with_short_interest_context,
    count(*) FILTER (
        WHERE peak_ftd_history_percentile_band IS NOT NULL
          AND prior_14d_short_volume_ratio_avg IS NOT NULL
          AND aligned_short_interest_settlement_date IS NOT NULL
    ) AS fully_contextualized_episodes,
    count(*) FILTER (WHERE priced_observation_count = 0) AS episodes_without_value,
    count(*) FILTER (WHERE is_left_censored) AS left_censored_episodes,
    count(*) FILTER (WHERE is_right_censored) AS right_censored_episodes,
    count(*) FILTER (WHERE crosses_primary_period_end) AS cutoff_crossing_episodes
FROM market_structure.ftd_episodes;

-- Longest episodes and largest balance-day totals help check the grouping.
(SELECT
    'longest' AS review_type,
    episode_id,
    security_id,
    episode_start_date,
    episode_end_date,
    observation_count,
    max_fails_quantity,
    ftd_balance_days
 FROM market_structure.ftd_episodes
 ORDER BY observation_count DESC, duration_calendar_days DESC
 LIMIT 15)
UNION ALL
(SELECT
    'largest_balance_days',
    episode_id,
    security_id,
    episode_start_date,
    episode_end_date,
    observation_count,
    max_fails_quantity,
    ftd_balance_days
 FROM market_structure.ftd_episodes
 ORDER BY ftd_balance_days DESC
 LIMIT 15);

-- Recurrent securities are reviewed without joining episodes across gaps.
SELECT
    security_id,
    count(*) AS episodes,
    min(episode_start_date) AS first_episode_start,
    max(episode_end_date) AS last_episode_end,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY days_since_previous_episode)
        AS median_days_between_episodes
FROM market_structure.ftd_episodes
GROUP BY security_id
ORDER BY episodes DESC, security_id
LIMIT 15;

SELECT
    pg_size_pretty(pg_relation_size('market_structure.ftd_episodes')) AS table_size,
    pg_size_pretty(pg_indexes_size('market_structure.ftd_episodes')) AS index_size,
    pg_size_pretty(pg_total_relation_size('market_structure.ftd_episodes'))
        AS total_size;
