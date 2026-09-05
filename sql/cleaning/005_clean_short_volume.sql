CREATE TABLE market_structure.short_volume_daily AS
WITH normalized AS (
    SELECT
        raw.*,
        market_structure.symbol_match_key(raw.symbol) AS symbol_match_key,
        upper(regexp_replace(btrim(raw.market), '\s+', '', 'g')) AS market_normalized
    FROM market_structure.raw_short_volume AS raw
),
-- If two raw symbols collapse to one key on the same date, neither is allowed
-- to inherit a security ID from that normalized key.
source_key_counts AS (
    SELECT
        trade_date,
        symbol_match_key,
        count(DISTINCT symbol)::integer AS source_symbol_count
    FROM normalized
    WHERE symbol_match_key IS NOT NULL
    GROUP BY trade_date, symbol_match_key
)
SELECT
    raw.trade_date,
    raw.symbol AS symbol_raw,
    raw.symbol_match_key,
    raw.symbol <> raw.symbol_match_key AS symbol_format_changed,
    coalesce(source_keys.source_symbol_count > 1, false) AS symbol_normalization_collision,
    raw.market AS market_raw,
    raw.market_normalized,
    raw.short_volume,
    raw.short_exempt_volume,
    raw.total_volume,
    raw.total_volume <= 0 AS nonpositive_total_volume,
    raw.short_volume > raw.total_volume AS short_volume_gt_total,
    raw.short_exempt_volume > raw.short_volume AS short_exempt_gt_short,
    CASE
        WHEN raw.symbol_match_key IS NULL THEN 'INVALID_SYMBOL'
        WHEN raw.total_volume <= 0 THEN 'NONPOSITIVE_TOTAL_VOLUME'
        WHEN raw.short_volume > raw.total_volume THEN 'SHORT_VOLUME_GT_TOTAL'
        WHEN raw.short_exempt_volume > raw.short_volume THEN 'SHORT_EXEMPT_GT_SHORT'
        ELSE 'VALID'
    END AS quality_status,
    CASE
        WHEN source_keys.source_symbol_count > 1 THEN NULL
        WHEN exact_map.candidate_count = 1 THEN exact_map.security_id
        WHEN exact_map.candidate_count IS NULL AND range_map.candidate_count = 1
            THEN range_map.security_id
    END AS security_id,
    CASE
        WHEN source_keys.source_symbol_count > 1 THEN 'AMBIGUOUS'
        WHEN exact_map.candidate_count = 1 THEN 'MATCHED'
        WHEN exact_map.candidate_count > 1 THEN 'AMBIGUOUS'
        WHEN range_map.candidate_count = 1 THEN 'MATCHED'
        WHEN range_map.candidate_count > 1 THEN 'AMBIGUOUS'
        ELSE 'UNRESOLVED'
    END AS identity_status,
    CASE
        WHEN source_keys.source_symbol_count > 1 THEN NULL
        WHEN exact_map.candidate_count = 1 THEN 'HIGH'
        WHEN exact_map.candidate_count IS NULL AND range_map.candidate_count = 1 THEN 'MEDIUM'
    END AS mapping_confidence,
    CASE
        WHEN source_keys.source_symbol_count > 1
            THEN 'SOURCE_SYMBOL_NORMALIZATION_COLLISION'
        WHEN exact_map.candidate_count = 1 THEN 'SEC_FTD_SAME_DATE'
        WHEN exact_map.candidate_count > 1 THEN 'SEC_FTD_SAME_DATE_AMBIGUOUS'
        WHEN range_map.candidate_count = 1 THEN 'SEC_FTD_OBSERVED_DATE_RANGE'
        WHEN range_map.candidate_count > 1 THEN 'SEC_FTD_DATE_RANGE_AMBIGUOUS'
    END AS mapping_method,
    coalesce(exact_map.candidate_count, range_map.candidate_count, 0)::integer
        AS identity_candidate_count,
    raw.source_file,
    raw.source_row_number,
    raw.ingested_at
FROM normalized AS raw
-- Prefer exact-date SEC evidence. Use an observed range only when no exact
-- evidence exists, and leave multiple candidates ambiguous.
LEFT JOIN source_key_counts AS source_keys
    ON source_keys.trade_date = raw.trade_date
   AND source_keys.symbol_match_key = raw.symbol_match_key
LEFT JOIN market_structure.security_symbol_date AS exact_map
    ON exact_map.symbol_match_key = raw.symbol_match_key
   AND exact_map.observation_date = raw.trade_date
LEFT JOIN market_structure.security_symbol_range AS range_map
    ON exact_map.symbol_match_key IS NULL
   AND range_map.symbol_match_key = raw.symbol_match_key
   AND raw.trade_date BETWEEN range_map.evidence_from AND range_map.evidence_to;

ALTER TABLE market_structure.short_volume_daily
    ALTER COLUMN trade_date SET NOT NULL,
    ALTER COLUMN symbol_raw SET NOT NULL,
    ALTER COLUMN symbol_normalization_collision SET NOT NULL,
    ALTER COLUMN market_raw SET NOT NULL,
    ALTER COLUMN short_volume SET NOT NULL,
    ALTER COLUMN short_exempt_volume SET NOT NULL,
    ALTER COLUMN total_volume SET NOT NULL,
    ALTER COLUMN quality_status SET NOT NULL,
    ALTER COLUMN identity_status SET NOT NULL,
    ALTER COLUMN identity_candidate_count SET NOT NULL,
    ALTER COLUMN source_file SET NOT NULL,
    ALTER COLUMN source_row_number SET NOT NULL,
    ADD PRIMARY KEY (source_file, source_row_number),
    ADD FOREIGN KEY (security_id) REFERENCES market_structure.security_identity,
    ADD CHECK (quality_status IN (
        'VALID', 'INVALID_SYMBOL', 'NONPOSITIVE_TOTAL_VOLUME',
        'SHORT_VOLUME_GT_TOTAL', 'SHORT_EXEMPT_GT_SHORT'
    )),
    ADD CHECK (identity_status IN ('MATCHED', 'AMBIGUOUS', 'UNRESOLVED')),
    ADD CHECK (mapping_confidence IS NULL OR mapping_confidence IN ('HIGH', 'MEDIUM'));

CREATE INDEX short_volume_daily_security_date_idx
    ON market_structure.short_volume_daily (security_id, trade_date)
    WHERE security_id IS NOT NULL;
CREATE INDEX short_volume_daily_date_brin
    ON market_structure.short_volume_daily USING brin (trade_date);
