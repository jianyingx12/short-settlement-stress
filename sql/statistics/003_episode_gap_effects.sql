-- Rebuild the nearby gap alternative and return its two context effects.
WITH cutoff AS (
    SELECT
        (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
            AS primary_end_date
    FROM market_structure.latest_complete_shared_month
), calendar AS (
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
), episodes AS (
    SELECT
        security_id,
        min(settlement_date) AS episode_start_date,
        max(settlement_date) AS episode_end_date,
        count(*) >= 2 AS is_persistent
    FROM tagged
    GROUP BY security_id, episode_number
), context AS (
    SELECT
        episode.security_id,
        episode.is_persistent,
        start_row.short_interest_full_sample_percentile,
        start_row.prior_14d_short_volume_ratio_percentile
    FROM episodes AS episode
    JOIN market_structure.ftd_analysis AS start_row
        ON start_row.security_id = episode.security_id
       AND start_row.settlement_date = episode.episode_start_date
    WHERE episode.episode_end_date <= (SELECT primary_end_date FROM cutoff)
      AND episode.episode_start_date > (SELECT min(settlement_date) FROM calendar)
), values AS (
    SELECT
        context.security_id,
        context.is_persistent,
        metric.name,
        metric.value::double precision
    FROM context
    CROSS JOIN LATERAL (VALUES
        ('short_interest_percentile', short_interest_full_sample_percentile),
        ('prior_short_volume_percentile', prior_14d_short_volume_ratio_percentile)
    ) AS metric(name, value)
    WHERE metric.value IS NOT NULL
), ranked AS (
    SELECT
        *,
        rank() OVER (PARTITION BY name ORDER BY value)
            + (count(*) OVER (PARTITION BY name, value) - 1) / 2.0 AS value_rank,
        count(*) OVER (PARTITION BY name, value) AS tie_count
    FROM values
)
SELECT
    name,
    is_persistent,
    count(*)::bigint AS observations,
    avg(value) AS mean_value,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY value) AS median_value,
    sum(value_rank) AS rank_sum,
    sum(tie_count * tie_count - 1)::double precision AS tie_term
FROM ranked
GROUP BY name, is_persistent
ORDER BY name, is_persistent;
