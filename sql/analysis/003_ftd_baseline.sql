CREATE TABLE market_structure.ftd_baseline AS
WITH securities AS (
    SELECT DISTINCT security_id
    FROM market_structure.ftd_daily
    WHERE quality_status = 'VALID'
      AND identity_status = 'MATCHED'
      AND mapping_confidence IN ('HIGH', 'MEDIUM')
      AND security_id IS NOT NULL
)
SELECT
    securities.security_id,
    count(*)::smallint AS observation_count,
    percentile_cont(ARRAY[
        0.01, 0.05, 0.10, 0.25, 0.50,
        0.75, 0.90, 0.95, 0.99, 0.995
    ]) WITHIN GROUP (ORDER BY baseline.fails_quantity) AS quantity_percentiles
FROM securities
CROSS JOIN LATERAL (
    -- Use each security's first 200 observations as its fixed prior baseline.
    SELECT ftd.quantity_fails AS fails_quantity
    FROM market_structure.ftd_daily AS ftd
    WHERE ftd.security_id = securities.security_id
      AND ftd.quality_status = 'VALID'
      AND ftd.identity_status = 'MATCHED'
      AND ftd.mapping_confidence IN ('HIGH', 'MEDIUM')
    ORDER BY ftd.settlement_date
    LIMIT 200
) AS baseline
GROUP BY securities.security_id;

ALTER TABLE market_structure.ftd_baseline
    ALTER COLUMN security_id SET NOT NULL,
    ALTER COLUMN observation_count SET NOT NULL,
    ALTER COLUMN quantity_percentiles SET NOT NULL,
    ADD PRIMARY KEY (security_id),
    ADD CHECK (observation_count BETWEEN 1 AND 200);

COMMENT ON TABLE market_structure.ftd_baseline IS
    'Fixed FTD quantity thresholds from each security''s first 200 observations.';
