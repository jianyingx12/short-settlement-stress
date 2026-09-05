-- Each checksum-valid SEC CUSIP becomes one security. CUSIPs are not merged
-- across corporate actions, so this is a security key rather than a company key.
CREATE TABLE market_structure.security_identity (
    security_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cusip_normalized text NOT NULL UNIQUE,
    issuer_name_match_key text,
    first_seen date NOT NULL,
    last_seen date NOT NULL,
    CHECK (market_structure.cusip_is_valid(cusip_normalized)),
    CHECK (first_seen <= last_seen)
);

WITH valid_cusips AS MATERIALIZED (
    SELECT upper(btrim(cusip)) AS cusip_normalized
    FROM market_structure.raw_ftd
    GROUP BY upper(btrim(cusip))
    HAVING market_structure.cusip_is_valid(upper(btrim(cusip)))
),
cusip_bounds AS (
    SELECT
        valid.cusip_normalized,
        min(ftd.settlement_date) AS first_seen,
        max(ftd.settlement_date) AS last_seen
    FROM market_structure.raw_ftd AS ftd
    JOIN valid_cusips AS valid
        ON valid.cusip_normalized = upper(btrim(ftd.cusip))
    GROUP BY valid.cusip_normalized
)
INSERT INTO market_structure.security_identity (
    cusip_normalized,
    issuer_name_match_key,
    first_seen,
    last_seen
)
SELECT
    bounds.cusip_normalized,
    latest_name.issuer_name_match_key,
    bounds.first_seen,
    bounds.last_seen
FROM cusip_bounds AS bounds
LEFT JOIN LATERAL (
    SELECT market_structure.issuer_name_match_key(ftd.description) AS issuer_name_match_key
    FROM market_structure.raw_ftd AS ftd
    WHERE ftd.cusip = bounds.cusip_normalized
      AND market_structure.issuer_name_match_key(ftd.description) IS NOT NULL
    ORDER BY ftd.settlement_date DESC, ftd.source_file DESC, ftd.source_row_number DESC
    LIMIT 1
) AS latest_name ON true
ORDER BY bounds.cusip_normalized;

CREATE TABLE market_structure.security_symbol_history (
    security_id bigint NOT NULL REFERENCES market_structure.security_identity,
    symbol_match_key text NOT NULL,
    example_source_symbol text NOT NULL,
    first_seen date NOT NULL,
    last_seen date NOT NULL,
    observation_count bigint NOT NULL CHECK (observation_count > 0),
    PRIMARY KEY (security_id, symbol_match_key),
    CHECK (first_seen <= last_seen)
);

INSERT INTO market_structure.security_symbol_history (
    security_id,
    symbol_match_key,
    example_source_symbol,
    first_seen,
    last_seen,
    observation_count
)
SELECT
    identity.security_id,
    market_structure.symbol_match_key(ftd.symbol),
    min(ftd.symbol),
    min(ftd.settlement_date),
    max(ftd.settlement_date),
    count(*)
FROM market_structure.raw_ftd AS ftd
JOIN market_structure.security_identity AS identity
    ON identity.cusip_normalized = upper(btrim(ftd.cusip))
WHERE market_structure.symbol_match_key(ftd.symbol) IS NOT NULL
GROUP BY identity.security_id, market_structure.symbol_match_key(ftd.symbol);

CREATE INDEX security_symbol_history_match_range_idx
    ON market_structure.security_symbol_history (symbol_match_key, first_seen, last_seen);

CREATE TABLE market_structure.security_symbol_range (
    symbol_match_key text NOT NULL,
    evidence_from date NOT NULL,
    evidence_to date NOT NULL,
    candidate_count integer NOT NULL CHECK (candidate_count >= 0),
    security_id bigint REFERENCES market_structure.security_identity,
    mapping_status text NOT NULL CHECK (
        mapping_status IN ('MATCHED', 'AMBIGUOUS', 'UNRESOLVED')
    ),
    PRIMARY KEY (symbol_match_key, evidence_from),
    CHECK (evidence_from <= evidence_to),
    CHECK ((candidate_count = 1) = (security_id IS NOT NULL))
);

-- Turn possibly overlapping CUSIP histories into non-overlapping evidence
-- segments. A segment receives an ID only when exactly one CUSIP is possible.
WITH boundaries AS (
    SELECT symbol_match_key, first_seen AS boundary_date
    FROM market_structure.security_symbol_history

    UNION

    SELECT symbol_match_key, last_seen + 1 AS boundary_date
    FROM market_structure.security_symbol_history
),
segments AS (
    SELECT
        symbol_match_key,
        boundary_date AS evidence_from,
        lead(boundary_date) OVER (
            PARTITION BY symbol_match_key
            ORDER BY boundary_date
        ) - 1 AS evidence_to
    FROM boundaries
),
candidate_counts AS (
    SELECT
        segment.symbol_match_key,
        segment.evidence_from,
        segment.evidence_to,
        count(DISTINCT history.security_id)::integer AS candidate_count,
        min(history.security_id) AS security_id
    FROM segments AS segment
    LEFT JOIN market_structure.security_symbol_history AS history
        ON history.symbol_match_key = segment.symbol_match_key
       AND segment.evidence_from BETWEEN history.first_seen AND history.last_seen
    WHERE segment.evidence_to IS NOT NULL
    GROUP BY segment.symbol_match_key, segment.evidence_from, segment.evidence_to
)
INSERT INTO market_structure.security_symbol_range (
    symbol_match_key,
    evidence_from,
    evidence_to,
    candidate_count,
    security_id,
    mapping_status
)
SELECT
    symbol_match_key,
    evidence_from,
    evidence_to,
    candidate_count,
    CASE WHEN candidate_count = 1 THEN security_id END,
    CASE
        WHEN candidate_count = 1 THEN 'MATCHED'
        WHEN candidate_count > 1 THEN 'AMBIGUOUS'
        ELSE 'UNRESOLVED'
    END
FROM candidate_counts;

CREATE INDEX security_symbol_range_lookup_idx
    ON market_structure.security_symbol_range (symbol_match_key, evidence_from, evidence_to);

COMMENT ON TABLE market_structure.security_identity IS
    'One identity per valid SEC FTD CUSIP. CUSIP changes are not automatically merged.';

COMMENT ON TABLE market_structure.security_symbol_history IS
    'Date bounds observed directly in SEC FTD data; gaps outside these bounds are not inferred.';

COMMENT ON TABLE market_structure.security_symbol_range IS
    'Non-overlapping date segments derived from observed SEC symbol histories.';
