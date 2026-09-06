DROP TABLE IF EXISTS ftd_alignment_fixture;

CREATE TEMP TABLE ftd_alignment_fixture AS
WITH ftd AS (
    SELECT
        security_id,
        observation_number,
        date '2025-01-10' + observation_number - 1 AS settlement_date,
        CASE WHEN security_id = 'security-a'
            THEN observation_number::bigint
            ELSE observation_number::bigint * 10
        END AS fails_quantity,
        CASE WHEN observation_number = 205 THEN NULL ELSE 2.0 END AS reference_price
    FROM (VALUES ('security-a'), ('security-b')) AS securities(security_id)
    CROSS JOIN generate_series(1, 205) AS observations(observation_number)
), calibration AS (
    SELECT
        security_id,
        percentile_cont(0.95) WITHIN GROUP (ORDER BY fails_quantity) AS p95
    FROM ftd
    WHERE observation_number <= 200
    GROUP BY security_id
), volume AS (
    SELECT
        security_id,
        date '2025-07-20' + day_number AS trade_date,
        CASE WHEN security_id = 'security-a'
            THEN day_number::double precision / 100
            ELSE day_number::double precision / 10
        END AS ratio
    FROM (VALUES ('security-a'), ('security-b')) AS securities(security_id)
    CROSS JOIN generate_series(1, 10) AS days(day_number)
), interest AS (
    SELECT security_id, settlement_date, short_position
    FROM (VALUES
        ('security-a', date '2025-07-25', 100::bigint),
        ('security-a', date '2025-07-28', 200::bigint),
        ('security-b', date '2025-07-28', 2000::bigint),
        ('security-a', date '2025-08-01', 300::bigint)
    ) AS cycles(security_id, settlement_date, short_position)
)
SELECT
    ftd.*,
    CASE WHEN reference_price IS NOT NULL
        THEN fails_quantity * reference_price END AS ftd_value,
    CASE WHEN observation_number > 200
        THEN fails_quantity >= calibration.p95 END AS exceeds_p95,
    aligned_volume.trade_date AS prior_trade_date,
    aligned_volume.ratio AS prior_ratio,
    aligned_interest.settlement_date AS interest_date,
    aligned_interest.short_position
FROM ftd
JOIN calibration USING (security_id)
LEFT JOIN LATERAL (
    SELECT volume.trade_date, volume.ratio
    FROM volume
    WHERE volume.security_id = ftd.security_id
      AND volume.trade_date < ftd.settlement_date
    ORDER BY volume.trade_date DESC
    LIMIT 1
) AS aligned_volume ON true
LEFT JOIN LATERAL (
    SELECT interest.*
    FROM interest
    WHERE interest.security_id = ftd.security_id
      AND interest.settlement_date <= ftd.settlement_date
    ORDER BY interest.settlement_date DESC
    LIMIT 1
) AS aligned_interest ON true;

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM ftd_alignment_fixture) = 410,
        'fixture multiplied or dropped an FTD row';
    ASSERT (SELECT exceeds_p95 IS NULL FROM ftd_alignment_fixture
            WHERE security_id = 'security-a' AND observation_number = 200),
        'FTD row was classified before completing the baseline';
    ASSERT (SELECT exceeds_p95 FROM ftd_alignment_fixture
            WHERE security_id = 'security-a' AND observation_number = 201),
        'FTD baseline threshold was not applied';
    ASSERT (SELECT ftd_value IS NULL FROM ftd_alignment_fixture
            WHERE security_id = 'security-a' AND observation_number = 205),
        'missing price produced an FTD value';
    ASSERT (
        SELECT prior_trade_date < settlement_date AND abs(prior_ratio - 0.08) < 1e-12
        FROM ftd_alignment_fixture
        WHERE security_id = 'security-a' AND observation_number = 201
    ), 'short-volume alignment used the wrong date or security';
    ASSERT (
        SELECT interest_date = date '2025-07-28' AND short_position = 2000
        FROM ftd_alignment_fixture
        WHERE security_id = 'security-b' AND observation_number = 201
    ), 'short-interest alignment used the wrong date or security';
END;
$$;

DROP TABLE ftd_alignment_fixture;
