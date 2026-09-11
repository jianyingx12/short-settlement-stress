CREATE TABLE market_structure.ftd_episodes AS
WITH calendar AS (
    SELECT
        settlement_date,
        row_number() OVER (ORDER BY settlement_date) AS settlement_date_number
    FROM (
        SELECT DISTINCT settlement_date
        FROM market_structure.ftd_analysis
    ) AS dates
), ordered AS (
    SELECT
        ftd.*,
        calendar.settlement_date_number,
        lag(ftd.settlement_date) OVER security_history AS previous_ftd_date,
        lag(calendar.settlement_date_number) OVER security_history
            AS previous_settlement_date_number
    FROM market_structure.ftd_analysis AS ftd
    JOIN calendar USING (settlement_date)
    WINDOW security_history AS (
        PARTITION BY security_id
        ORDER BY settlement_date
    )
), tagged AS (
    SELECT
        ordered.*,
        CASE
            WHEN previous_ftd_date IS NULL THEN 1
            WHEN settlement_date_number - previous_settlement_date_number <> 1 THEN 1
            WHEN settlement_date - previous_ftd_date > 4 THEN 1
            ELSE 0
        END AS starts_new_episode
    FROM ordered
), numbered AS (
    -- Consecutive means the next observed SEC date, with no gap longer than four days.
    SELECT
        tagged.*,
        sum(starts_new_episode) OVER (
            PARTITION BY security_id
            ORDER BY settlement_date
            ROWS UNBOUNDED PRECEDING
        ) AS episode_number
    FROM tagged
), aggregated AS (
    SELECT
        security_id,
        episode_number,
        CASE
            WHEN bool_or(ftd_mapping_confidence = 'MEDIUM') THEN 'MEDIUM'
            ELSE 'HIGH'
        END AS ftd_mapping_confidence,
        min(settlement_date) AS episode_start_date,
        max(settlement_date) AS episode_end_date,
        max(settlement_date) - min(settlement_date) + 1
            AS duration_calendar_days,
        count(*)::integer AS observation_count,
        max(fails_quantity) AS max_fails_quantity,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY fails_quantity)
            AS median_fails_quantity,
        sum(fails_quantity) AS ftd_balance_days,
        (array_agg(settlement_date ORDER BY fails_quantity DESC, settlement_date))[1]
            AS peak_date,
        count(ftd_value)::integer AS priced_observation_count,
        max(ftd_value) AS max_ftd_value,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY ftd_value)
            AS median_ftd_value,
        max(ftd_quantity_history_percentile_band)
            AS peak_ftd_history_percentile_band,
        bool_or(exceeds_baseline_p95) AS reaches_baseline_p95,
        bool_or(exceeds_baseline_p99) AS reaches_baseline_p99,
        bool_or(exceeds_baseline_p995) AS reaches_baseline_p995
    FROM numbered
    GROUP BY security_id, episode_number
), recurrence AS (
    SELECT
        aggregated.*,
        lag(episode_end_date) OVER security_episodes AS previous_episode_end_date,
        lead(episode_start_date) OVER security_episodes AS next_episode_start_date
    FROM aggregated
    WINDOW security_episodes AS (
        PARTITION BY security_id
        ORDER BY episode_start_date
    )
), boundaries AS (
    SELECT
        min(settlement_date) AS first_available_date,
        max(settlement_date) AS last_available_date,
        (SELECT (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
         FROM market_structure.latest_complete_shared_month) AS primary_end_date
    FROM market_structure.ftd_analysis
), contextualized AS (
    SELECT
        recurrence.*,
        recurrence.episode_start_date - recurrence.previous_episode_end_date
            AS days_since_previous_episode,
        recurrence.next_episode_start_date - recurrence.episode_end_date
            AS days_until_next_episode,
        recurrence.episode_start_date = boundaries.first_available_date
            AS is_left_censored,
        recurrence.episode_end_date = boundaries.last_available_date
            AS is_right_censored,
        recurrence.episode_start_date <= boundaries.primary_end_date
          AND recurrence.episode_end_date > boundaries.primary_end_date
            AS crosses_primary_period_end,
        recurrence.episode_end_date <= boundaries.primary_end_date
            AS is_primary_analysis_period,
        start_row.short_volume_mapping_confidence,
        start_row.prior_14d_short_volume_ratio_avg,
        start_row.prior_14d_short_volume_ratio_trend,
        start_row.prior_14d_short_volume_ratio_percentile,
        start_row.aligned_short_interest_settlement_date,
        start_row.days_since_short_interest_settlement,
        start_row.short_interest_mapping_confidence,
        start_row.short_interest_full_sample_percentile,
        start_row.days_to_cover,
        start_row.signed_log_short_interest_change
    FROM recurrence
    CROSS JOIN boundaries
    JOIN market_structure.ftd_analysis AS start_row
        ON start_row.security_id = recurrence.security_id
       AND start_row.settlement_date = recurrence.episode_start_date
)
SELECT
    row_number() OVER (ORDER BY security_id, episode_start_date) AS episode_id,
    security_id,
    episode_number,
    previous_episode_end_date,
    next_episode_start_date,
    days_since_previous_episode,
    days_until_next_episode,
    ftd_mapping_confidence,
    episode_start_date,
    episode_end_date,
    duration_calendar_days,
    observation_count,
    CASE WHEN observation_count = 1 THEN 'isolated' ELSE 'persistent' END
        AS episode_class,
    CASE
        WHEN observation_count = 1 THEN '1_observation'
        WHEN observation_count <= 3 THEN '2_to_3'
        WHEN observation_count <= 5 THEN '4_to_5'
        WHEN observation_count <= 10 THEN '6_to_10'
        ELSE '11_plus'
    END AS duration_group,
    max_fails_quantity,
    median_fails_quantity,
    ftd_balance_days,
    peak_date,
    priced_observation_count,
    max_ftd_value,
    median_ftd_value,
    peak_ftd_history_percentile_band,
    CASE
        WHEN reaches_baseline_p95 IS NULL THEN 'insufficient_history'
        WHEN reaches_baseline_p995 THEN 'p995_plus'
        WHEN reaches_baseline_p99 THEN 'p99_to_p995'
        WHEN reaches_baseline_p95 THEN 'p95_to_p99'
        ELSE 'below_p95'
    END AS intensity_group,
    is_left_censored,
    is_right_censored,
    crosses_primary_period_end,
    is_primary_analysis_period,
    short_volume_mapping_confidence,
    prior_14d_short_volume_ratio_avg,
    prior_14d_short_volume_ratio_trend,
    prior_14d_short_volume_ratio_percentile,
    aligned_short_interest_settlement_date,
    days_since_short_interest_settlement,
    short_interest_mapping_confidence,
    short_interest_full_sample_percentile,
    days_to_cover,
    signed_log_short_interest_change,
    CASE
        WHEN observation_count >= 2
         AND short_interest_full_sample_percentile IS NOT NULL
         AND prior_14d_short_volume_ratio_percentile IS NOT NULL THEN concat(
            'persistent_',
            CASE WHEN short_interest_full_sample_percentile >= 0.90
                THEN 'high_si_' ELSE 'lower_si_' END,
            CASE WHEN prior_14d_short_volume_ratio_percentile >= 0.90
                THEN 'high_activity' ELSE 'normal_activity' END
        )
    END AS persistent_regime
FROM contextualized;

COMMENT ON TABLE market_structure.ftd_episodes IS
    'One row per FTD episode using consecutive observed SEC settlement dates with a maximum four-day calendar gap.';

COMMENT ON COLUMN market_structure.ftd_episodes.ftd_balance_days IS
    'Sum of daily outstanding FTD balances within the episode; this is an intensity measure, not newly failed shares.';
