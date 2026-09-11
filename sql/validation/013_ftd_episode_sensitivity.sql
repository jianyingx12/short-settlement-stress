-- Allow one missing SEC settlement date, but never bridge more than seven days.
WITH calendar AS (
    SELECT
        settlement_date,
        row_number() OVER (ORDER BY settlement_date) AS date_number
    FROM (
        SELECT DISTINCT settlement_date
        FROM market_structure.ftd_analysis
    ) AS dates
), ordered AS (
    SELECT
        ftd.security_id,
        ftd.settlement_date,
        calendar.date_number,
        lag(ftd.settlement_date) OVER security_history AS previous_date,
        lag(calendar.date_number) OVER security_history AS previous_date_number
    FROM market_structure.ftd_analysis AS ftd
    JOIN calendar USING (settlement_date)
    WINDOW security_history AS (
        PARTITION BY security_id ORDER BY settlement_date
    )
), tagged AS (
    SELECT
        *,
        sum(CASE
            WHEN previous_date IS NULL THEN 1
            WHEN date_number - previous_date_number > 2 THEN 1
            WHEN settlement_date - previous_date > 7 THEN 1
            ELSE 0
        END) OVER (
            PARTITION BY security_id ORDER BY settlement_date
        ) AS episode_number
    FROM ordered
), alternative AS (
    SELECT
        security_id,
        episode_number,
        min(settlement_date) AS start_date,
        max(settlement_date) AS end_date,
        count(*) AS observation_count
    FROM tagged
    GROUP BY security_id, episode_number
), alternative_with_context AS (
    SELECT
        alternative.*,
        start_row.short_interest_full_sample_percentile,
        start_row.prior_14d_short_volume_ratio_percentile
    FROM alternative
    JOIN market_structure.ftd_analysis AS start_row
        ON start_row.security_id = alternative.security_id
       AND start_row.settlement_date = alternative.start_date
), rules AS (
    SELECT
        'strict_next_sec_date' AS gap_rule,
        count(*) AS episodes,
        avg((observation_count >= 2)::integer::double precision)
            AS persistent_share,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY observation_count)
            AS median_observations,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_calendar_days)
            AS median_calendar_days,
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY short_interest_full_sample_percentile
        ) FILTER (WHERE observation_count >= 2)
            AS persistent_median_short_interest_percentile,
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY prior_14d_short_volume_ratio_percentile
        ) FILTER (WHERE observation_count >= 2)
            AS persistent_median_short_volume_percentile
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
      AND NOT is_left_censored
    UNION ALL
    SELECT
        'allow_one_missing_sec_date',
        count(*),
        avg((observation_count >= 2)::integer::double precision),
        percentile_cont(0.5) WITHIN GROUP (ORDER BY observation_count),
        percentile_cont(0.5) WITHIN GROUP (ORDER BY end_date - start_date + 1),
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY short_interest_full_sample_percentile
        ) FILTER (WHERE observation_count >= 2),
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY prior_14d_short_volume_ratio_percentile
        ) FILTER (WHERE observation_count >= 2)
    FROM alternative_with_context
    WHERE end_date <= (
        SELECT (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
        FROM market_structure.latest_complete_shared_month
    )
      AND start_date > (SELECT min(settlement_date) FROM calendar)
)
SELECT * FROM rules ORDER BY gap_rule;

-- Check whether confidence restrictions change the class comparison.
WITH samples AS (
    SELECT
        'high_and_medium_context' AS sample,
        episode_class,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_percentile
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
      AND NOT is_left_censored
      AND ftd_mapping_confidence IN ('HIGH', 'MEDIUM')
      AND short_volume_mapping_confidence IN ('HIGH', 'MEDIUM')
      AND short_interest_mapping_confidence IN ('HIGH', 'MEDIUM')
      AND short_interest_full_sample_percentile IS NOT NULL
      AND prior_14d_short_volume_ratio_percentile IS NOT NULL
    UNION ALL
    SELECT
        'high_only_context',
        episode_class,
        short_interest_full_sample_percentile,
        prior_14d_short_volume_ratio_percentile
    FROM market_structure.ftd_episodes
    WHERE is_primary_analysis_period
      AND NOT is_left_censored
      AND ftd_mapping_confidence = 'HIGH'
      AND short_volume_mapping_confidence = 'HIGH'
      AND short_interest_mapping_confidence = 'HIGH'
      AND short_interest_full_sample_percentile IS NOT NULL
      AND prior_14d_short_volume_ratio_percentile IS NOT NULL
)
SELECT
    sample,
    episode_class,
    count(*) AS episodes,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY short_interest_full_sample_percentile
    ) AS median_short_interest_percentile,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY prior_14d_short_volume_ratio_percentile
    ) AS median_short_volume_percentile
FROM samples
GROUP BY sample, episode_class
ORDER BY sample, episode_class;

SELECT
    count(*) FILTER (WHERE is_left_censored) AS left_censored,
    count(*) FILTER (WHERE is_right_censored) AS right_censored,
    count(*) FILTER (WHERE crosses_primary_period_end) AS crossing_primary_end,
    count(*) FILTER (WHERE NOT is_primary_analysis_period) AS partial_period_episodes
FROM market_structure.ftd_episodes;
