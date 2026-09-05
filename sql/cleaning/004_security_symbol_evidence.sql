-- Reduce SEC observations to one symbol-to-CUSIP result per settlement date.
-- More than one candidate is preserved as ambiguous rather than forced to match.
CREATE TABLE market_structure.security_symbol_date AS
SELECT
    settlement_date AS observation_date,
    symbol_match_key,
    count(DISTINCT security_id)::integer AS candidate_count,
    CASE
        WHEN count(DISTINCT security_id) = 1 THEN min(security_id)
    END AS security_id,
    CASE
        WHEN count(DISTINCT security_id) = 1 THEN 'MATCHED'
        ELSE 'AMBIGUOUS'
    END AS mapping_status
FROM market_structure.ftd_daily
WHERE symbol_match_key IS NOT NULL
  AND security_id IS NOT NULL
GROUP BY settlement_date, symbol_match_key;

ALTER TABLE market_structure.security_symbol_date
    ALTER COLUMN observation_date SET NOT NULL,
    ALTER COLUMN symbol_match_key SET NOT NULL,
    ALTER COLUMN candidate_count SET NOT NULL,
    ALTER COLUMN mapping_status SET NOT NULL,
    ADD PRIMARY KEY (symbol_match_key, observation_date),
    ADD FOREIGN KEY (security_id) REFERENCES market_structure.security_identity,
    ADD CHECK (candidate_count > 0),
    ADD CHECK (mapping_status IN ('MATCHED', 'AMBIGUOUS'));

COMMENT ON TABLE market_structure.security_symbol_date IS
    'Exact-date SEC symbol evidence. Rows with multiple CUSIPs remain ambiguous.';
