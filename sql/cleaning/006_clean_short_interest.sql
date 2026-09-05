-- Publication date stays separate and null because it is not present in the
-- downloaded historical rows. Settlement date is never used as a substitute.
CREATE TABLE market_structure.short_interest_observation AS
WITH normalized AS (
    SELECT
        raw.*,
        market_structure.symbol_match_key(raw.symbol_code) AS symbol_match_key
    FROM market_structure.raw_short_interest AS raw
)
SELECT
    raw.settlement_date,
    NULL::date AS publication_date,
    raw.accounting_year_month_number,
    raw.symbol_code AS symbol_raw,
    raw.symbol_match_key,
    raw.issue_name AS issue_name_raw,
    raw.issuer_services_group_exchange_code AS exchange_code_raw,
    upper(btrim(raw.issuer_services_group_exchange_code)) AS exchange_code_normalized,
    raw.market_class_code AS market_class_raw,
    upper(btrim(raw.market_class_code)) AS market_class_normalized,
    upper(btrim(raw.market_class_code)) NOT IN ('OTC', 'OTCBB') AS primary_population,
    raw.current_short_position_quantity,
    raw.previous_short_position_quantity,
    raw.stock_split_flag,
    raw.average_daily_volume_quantity,
    raw.days_to_cover_quantity,
    raw.revision_flag,
    raw.change_percent,
    raw.change_previous_number,
    upper(btrim(coalesce(raw.revision_flag, ''))) = 'R' AS is_revision,
    upper(btrim(coalesce(raw.stock_split_flag, ''))) = 'S' AS has_stock_split,
    CASE
        WHEN raw.symbol_match_key IS NULL THEN 'INVALID_SYMBOL'
        WHEN raw.current_short_position_quantity < 0
          OR raw.previous_short_position_quantity < 0
          OR raw.average_daily_volume_quantity < 0
          OR raw.days_to_cover_quantity < 0 THEN 'INVALID_QUANTITY'
        ELSE 'VALID'
    END AS quality_status,
    CASE
        WHEN exact_map.candidate_count = 1 THEN exact_map.security_id
        WHEN exact_map.candidate_count IS NULL AND range_map.candidate_count = 1
            THEN range_map.security_id
    END AS security_id,
    CASE
        WHEN exact_map.candidate_count = 1 THEN 'MATCHED'
        WHEN exact_map.candidate_count > 1 THEN 'AMBIGUOUS'
        WHEN range_map.candidate_count = 1 THEN 'MATCHED'
        WHEN range_map.candidate_count > 1 THEN 'AMBIGUOUS'
        ELSE 'UNRESOLVED'
    END AS identity_status,
    CASE
        WHEN exact_map.candidate_count = 1 THEN 'HIGH'
        WHEN exact_map.candidate_count IS NULL AND range_map.candidate_count = 1 THEN 'MEDIUM'
    END AS mapping_confidence,
    CASE
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
-- Matching follows the same exact-date-then-evidence-range hierarchy as the
-- short-volume cleaner.
LEFT JOIN market_structure.security_symbol_date AS exact_map
    ON exact_map.symbol_match_key = raw.symbol_match_key
   AND exact_map.observation_date = raw.settlement_date
LEFT JOIN market_structure.security_symbol_range AS range_map
    ON exact_map.symbol_match_key IS NULL
   AND range_map.symbol_match_key = raw.symbol_match_key
   AND raw.settlement_date BETWEEN range_map.evidence_from AND range_map.evidence_to;

ALTER TABLE market_structure.short_interest_observation
    ALTER COLUMN settlement_date SET NOT NULL,
    ALTER COLUMN accounting_year_month_number SET NOT NULL,
    ALTER COLUMN symbol_raw SET NOT NULL,
    ALTER COLUMN primary_population SET NOT NULL,
    ALTER COLUMN quality_status SET NOT NULL,
    ALTER COLUMN identity_status SET NOT NULL,
    ALTER COLUMN identity_candidate_count SET NOT NULL,
    ALTER COLUMN source_file SET NOT NULL,
    ALTER COLUMN source_row_number SET NOT NULL,
    ADD PRIMARY KEY (source_file, source_row_number),
    ADD FOREIGN KEY (security_id) REFERENCES market_structure.security_identity,
    ADD CHECK (quality_status IN ('VALID', 'INVALID_SYMBOL', 'INVALID_QUANTITY')),
    ADD CHECK (identity_status IN ('MATCHED', 'AMBIGUOUS', 'UNRESOLVED')),
    ADD CHECK (mapping_confidence IS NULL OR mapping_confidence IN ('HIGH', 'MEDIUM'));

CREATE INDEX short_interest_observation_security_date_idx
    ON market_structure.short_interest_observation (security_id, settlement_date)
    WHERE security_id IS NOT NULL;
CREATE INDEX short_interest_observation_date_brin
    ON market_structure.short_interest_observation USING brin (settlement_date);

COMMENT ON COLUMN market_structure.short_interest_observation.publication_date IS
    'NULL because historical publication dates are not present in the downloaded files.';
