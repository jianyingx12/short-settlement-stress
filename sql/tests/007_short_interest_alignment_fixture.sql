DROP TABLE IF EXISTS short_interest_alignment_fixture;

CREATE TEMP TABLE short_interest_alignment_fixture AS
WITH volume AS (
    SELECT
        security_id,
        date '2026-01-01' + day_number - 1 AS trade_date,
        CASE
            WHEN security_id = 'security-a' THEN day_number / 100.0
            ELSE day_number / 10.0
        END AS ratio
    FROM (VALUES ('security-a'), ('security-b')) AS securities(security_id)
    CROSS JOIN generate_series(1, 10) AS days(day_number)
), interest AS (
    SELECT security_id, settlement_date
    FROM (VALUES
        ('security-a', date '2026-01-10'),
        ('security-b', date '2026-01-10')
    ) AS observations(security_id, settlement_date)
)
SELECT
    interest.security_id,
    interest.settlement_date,
    aligned.first_trade_date,
    aligned.last_trade_date,
    aligned.observation_count,
    aligned.ratio_avg
FROM interest
LEFT JOIN LATERAL (
    SELECT
        min(trade_date) AS first_trade_date,
        max(trade_date) AS last_trade_date,
        count(*) AS observation_count,
        avg(ratio) AS ratio_avg
    FROM (
        SELECT volume.trade_date, volume.ratio
        FROM volume
        WHERE volume.security_id = interest.security_id
          AND volume.trade_date < interest.settlement_date
        ORDER BY volume.trade_date DESC
        LIMIT 3
    ) AS preceding
) AS aligned ON true;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM short_interest_alignment_fixture) = 2,
        'fixture multiplied short-interest rows';
    ASSERT (
        SELECT observation_count = 3
           AND first_trade_date = date '2026-01-07'
           AND last_trade_date = date '2026-01-09'
           AND abs(ratio_avg - 0.08) < 1e-12
        FROM short_interest_alignment_fixture
        WHERE security_id = 'security-a'
    ), 'preceding window included the settlement date or wrong boundary';
    ASSERT (
        SELECT abs(ratio_avg - 0.8) < 1e-12
        FROM short_interest_alignment_fixture
        WHERE security_id = 'security-b'
    ), 'preceding window crossed security boundaries';
    ASSERT (
        SELECT CASE WHEN previous_position > 0
            THEN (current_position - previous_position)::double precision
                / previous_position
        END IS NULL
        FROM (VALUES (10::bigint, 0::bigint))
            AS positions(current_position, previous_position)
    ), 'zero previous position produced a percentage change';
END;
$$;

DROP TABLE short_interest_alignment_fixture;
