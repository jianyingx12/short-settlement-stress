DROP TABLE IF EXISTS ftd_episode_fixture;

CREATE TEMP TABLE ftd_episode_fixture AS
WITH calendar AS (
    SELECT
        settlement_date,
        row_number() OVER (ORDER BY settlement_date) AS date_number
    FROM (VALUES
        (date '2026-01-02'),
        (date '2026-01-05'),
        (date '2026-01-06'),
        (date '2026-01-07'),
        (date '2026-01-08'),
        (date '2026-01-09'),
        (date '2026-01-12'),
        (date '2026-01-16'),
        (date '2026-01-20'),
        (date '2026-02-10')
    ) AS dates(settlement_date)
), observations AS (
    SELECT security_id, settlement_date, fails_quantity
    FROM (VALUES
        ('security-a', date '2026-01-02', 100::bigint),
        ('security-a', date '2026-01-05', 200::bigint),
        ('security-a', date '2026-01-06', 300::bigint),
        ('security-a', date '2026-01-08', 400::bigint),
        ('security-a', date '2026-01-09', 500::bigint),
        ('security-a', date '2026-01-12', 600::bigint),
        ('security-a', date '2026-01-16', 700::bigint),
        ('security-a', date '2026-01-20', 800::bigint),
        ('security-a', date '2026-02-10', 900::bigint),
        ('security-b', date '2026-01-02', 1000::bigint),
        ('security-b', date '2026-01-05', 2000::bigint)
    ) AS rows(security_id, settlement_date, fails_quantity)
), ordered AS (
    SELECT
        observations.*,
        calendar.date_number,
        lag(observations.settlement_date) OVER security_history AS previous_date,
        lag(calendar.date_number) OVER security_history AS previous_date_number
    FROM observations
    JOIN calendar USING (settlement_date)
    WINDOW security_history AS (
        PARTITION BY security_id ORDER BY settlement_date
    )
), numbered AS (
    SELECT
        *,
        sum(CASE
            WHEN previous_date IS NULL THEN 1
            WHEN date_number - previous_date_number <> 1 THEN 1
            WHEN settlement_date - previous_date > 4 THEN 1
            ELSE 0
        END) OVER (
            PARTITION BY security_id ORDER BY settlement_date
        ) AS episode_number
    FROM ordered
), episodes AS (
    SELECT
        security_id,
        episode_number,
        min(settlement_date) AS start_date,
        max(settlement_date) AS end_date,
        count(*) AS observation_count,
        sum(fails_quantity) AS balance_days,
        min(settlement_date) - 1 AS prior_volume_date,
        min(settlement_date) AS aligned_interest_date
    FROM numbered
    GROUP BY security_id, episode_number
)
SELECT
    episodes.*,
    lag(end_date) OVER security_episodes AS previous_episode_end,
    start_date = date '2026-01-02' AS is_left_censored,
    end_date = date '2026-02-10' AS is_right_censored
FROM episodes
WINDOW security_episodes AS (
    PARTITION BY security_id ORDER BY start_date
);

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM ftd_episode_fixture) = 4,
        'fixture produced the wrong episode count';
    ASSERT (
        SELECT observation_count = 3
           AND end_date = date '2026-01-06'
           AND balance_days = 600
        FROM ftd_episode_fixture
        WHERE security_id = 'security-a' AND start_date = date '2026-01-02'
    ), 'weekend observations did not form the expected episode';
    ASSERT (
        SELECT observation_count = 5 AND end_date = date '2026-01-20'
        FROM ftd_episode_fixture
        WHERE security_id = 'security-a' AND start_date = date '2026-01-08'
    ), 'holiday gaps of four calendar days broke the episode';
    ASSERT (
        SELECT previous_episode_end = date '2026-01-06'
        FROM ftd_episode_fixture
        WHERE security_id = 'security-a' AND start_date = date '2026-01-08'
    ), 'recurrence did not preserve the previous episode';
    ASSERT (
        SELECT observation_count = 1 AND is_right_censored
        FROM ftd_episode_fixture
        WHERE security_id = 'security-a' AND start_date = date '2026-02-10'
    ), 'the long source gap did not break or censor the episode';
    ASSERT (
        SELECT observation_count = 2 AND balance_days = 3000
        FROM ftd_episode_fixture
        WHERE security_id = 'security-b'
    ), 'episodes crossed security boundaries';
    ASSERT NOT EXISTS (
        SELECT 1
        FROM ftd_episode_fixture
        WHERE prior_volume_date >= start_date
           OR aligned_interest_date > start_date
    ), 'episode context crossed its allowed date boundary';
END;
$$;

DROP TABLE ftd_episode_fixture;
