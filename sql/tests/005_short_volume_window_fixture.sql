-- A tiny deterministic fixture verifies observation windows and security partitions.
DROP TABLE IF EXISTS short_volume_window_fixture;

CREATE TEMP TABLE short_volume_window_fixture AS
WITH fixture AS (
    SELECT
        security_id,
        observation_number,
        observation_number::double precision / 100.0 AS ratio
    FROM (VALUES ('security-a'), ('security-b')) AS securities(security_id)
    CROSS JOIN generate_series(1, 35) AS observations(observation_number)
), calculated AS (
    SELECT
        *,
        avg(ratio) OVER window_5d AS avg_5d,
        avg(ratio) OVER window_14d AS avg_14d,
        avg(ratio) OVER window_30d AS avg_30d,
        lag(ratio) OVER security_history AS previous_ratio,
        avg(ratio) OVER prior_history AS history_mean,
        stddev_samp(ratio) OVER prior_history AS history_std
    FROM fixture
    WINDOW
        security_history AS (
            PARTITION BY security_id ORDER BY observation_number
        ),
        window_5d AS (
            PARTITION BY security_id ORDER BY observation_number
            ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
        ),
        window_14d AS (
            PARTITION BY security_id ORDER BY observation_number
            ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
        ),
        window_30d AS (
            PARTITION BY security_id ORDER BY observation_number
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ),
        prior_history AS (
            PARTITION BY security_id ORDER BY observation_number
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        )
)
SELECT * FROM calculated;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM short_volume_window_fixture) = 70,
        'fixture securities leaked across partitions';
    ASSERT (SELECT abs(avg_5d - 0.03) < 1e-12 FROM short_volume_window_fixture
            WHERE security_id = 'security-a' AND observation_number = 5),
        '5-observation average is incorrect';
    ASSERT (SELECT abs(avg_14d - 0.075) < 1e-12 FROM short_volume_window_fixture
            WHERE security_id = 'security-a' AND observation_number = 14),
        '14-observation average is incorrect';
    ASSERT (SELECT abs(avg_30d - 0.155) < 1e-12 FROM short_volume_window_fixture
            WHERE security_id = 'security-a' AND observation_number = 30),
        '30-observation average is incorrect';
    ASSERT (SELECT abs(previous_ratio - 0.20) < 1e-12
            FROM short_volume_window_fixture
            WHERE security_id = 'security-b' AND observation_number = 21),
        'lag crossed a security boundary or used the wrong observation';
    ASSERT (
        SELECT abs((ratio - history_mean) / history_std - 1.7748239349298849) < 1e-12
        FROM short_volume_window_fixture
        WHERE security_id = 'security-a' AND observation_number = 21
    ), 'expanding z-score did not use only prior observations';

    ASSERT (
        SELECT ratio IS NULL
        FROM (
            SELECT CASE
                WHEN total_volume > 0
                    THEN short_volume::double precision / total_volume
            END AS ratio
            FROM (VALUES (10::bigint, 0::bigint))
                AS zero_denominator(short_volume, total_volume)
        ) AS calculated_ratio
    ), 'zero total volume produced a ratio';

    ASSERT abs(
        2::double precision / 10
        - 0.2
    ) < 1e-12, 'short-exempt ratio fixture is incorrect';
END;
$$;

DROP TABLE short_volume_window_fixture;
