DO $$
DECLARE
    source_rows bigint;
    episode_rows bigint;
    source_balance numeric;
    episode_balance numeric;
    invalid_rows bigint;
BEGIN
    SELECT count(*), sum(fails_quantity)
    INTO source_rows, source_balance
    FROM market_structure.ftd_analysis;

    SELECT sum(observation_count), sum(ftd_balance_days)
    INTO episode_rows, episode_balance
    FROM market_structure.ftd_episodes;

    ASSERT episode_rows = source_rows,
        'FTD observations do not reconcile with episode counts';
    ASSERT episode_balance = source_balance,
        'episode balance-days do not reconcile with daily balances';

    WITH calendar AS (
        SELECT
            settlement_date,
            row_number() OVER (ORDER BY settlement_date) AS date_number
        FROM (
            SELECT DISTINCT settlement_date
            FROM market_structure.ftd_analysis
        ) AS dates
    )
    SELECT count(*)
    INTO invalid_rows
    FROM market_structure.ftd_episodes AS episode
    JOIN calendar AS first_date
        ON first_date.settlement_date = episode.episode_start_date
    JOIN calendar AS last_date
        ON last_date.settlement_date = episode.episode_end_date
    WHERE episode.observation_count
            <> last_date.date_number - first_date.date_number + 1
       OR (episode.episode_class = 'isolated' AND episode.observation_count <> 1)
       OR (episode.episode_class = 'persistent' AND episode.observation_count < 2)
       OR episode.peak_date NOT BETWEEN episode_start_date AND episode_end_date
       OR (episode.prior_14d_short_volume_ratio_avg IS NOT NULL
            AND NOT EXISTS (
                SELECT 1
                FROM market_structure.ftd_analysis AS start_row
                WHERE start_row.security_id = episode.security_id
                  AND start_row.settlement_date = episode.episode_start_date
                  AND start_row.prior_short_volume_trade_date
                        < episode.episode_start_date
            ))
       OR episode.aligned_short_interest_settlement_date > episode.episode_start_date;

    ASSERT invalid_rows = 0,
        'episode boundaries, classes, or start-date context are invalid';

    SELECT count(*)
    INTO invalid_rows
    FROM (
        SELECT
            episode_id,
            row_number() OVER (ORDER BY security_id, episode_start_date)
                AS expected_episode_id
        FROM market_structure.ftd_episodes
    ) AS numbered
    WHERE episode_id <> expected_episode_id;

    ASSERT invalid_rows = 0,
        'episode IDs are not in deterministic security and date order';
END;
$$;

DO $$
DECLARE
    first_date date;
    last_date date;
    cutoff_date date;
    invalid_censoring bigint;
BEGIN
    SELECT min(settlement_date), max(settlement_date)
    INTO first_date, last_date
    FROM market_structure.ftd_analysis;

    SELECT (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
    INTO cutoff_date
    FROM market_structure.latest_complete_shared_month;

    SELECT count(*)
    INTO invalid_censoring
    FROM market_structure.ftd_episodes
    WHERE is_left_censored IS DISTINCT FROM (episode_start_date = first_date)
       OR is_right_censored IS DISTINCT FROM (episode_end_date = last_date)
       OR crosses_primary_period_end IS DISTINCT FROM (
            episode_start_date <= cutoff_date AND episode_end_date > cutoff_date
       )
       OR is_primary_analysis_period IS DISTINCT FROM
            (episode_end_date <= cutoff_date);

    ASSERT invalid_censoring = 0,
        'episode censoring or primary-period flags are invalid';
END;
$$;
