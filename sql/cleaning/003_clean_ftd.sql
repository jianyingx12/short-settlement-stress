-- Preserve the source values while adding comparison keys and explicit
-- missing-value flags. A blank SEC symbol is never fabricated.
CREATE TABLE market_structure.ftd_daily AS
SELECT
    raw.settlement_date,
    raw.cusip AS cusip_raw,
    upper(btrim(raw.cusip)) AS cusip_normalized,
    identity.security_id IS NOT NULL AS cusip_valid,
    raw.symbol AS symbol_raw,
    market_structure.symbol_match_key(raw.symbol) AS symbol_match_key,
    raw.description AS issuer_name_raw,
    raw.quantity_fails,
    raw.reference_price,
    raw.reference_price_raw,
    raw.symbol IS NULL AS symbol_missing,
    raw.reference_price IS NULL AS reference_price_missing,
    CASE
        WHEN identity.security_id IS NULL THEN 'INVALID_CUSIP'
        WHEN raw.quantity_fails < 0 THEN 'INVALID_QUANTITY'
        ELSE 'VALID'
    END AS quality_status,
    identity.security_id,
    CASE WHEN identity.security_id IS NULL THEN 'UNRESOLVED' ELSE 'MATCHED' END AS identity_status,
    CASE WHEN identity.security_id IS NULL THEN NULL ELSE 'HIGH' END AS mapping_confidence,
    CASE WHEN identity.security_id IS NULL THEN NULL ELSE 'SEC_FTD_CUSIP' END AS mapping_method,
    raw.source_file,
    raw.source_member,
    raw.source_row_number,
    raw.ingested_at
FROM market_structure.raw_ftd AS raw
LEFT JOIN market_structure.security_identity AS identity
    ON identity.cusip_normalized = upper(btrim(raw.cusip));

ALTER TABLE market_structure.ftd_daily
    ALTER COLUMN settlement_date SET NOT NULL,
    ALTER COLUMN cusip_raw SET NOT NULL,
    ALTER COLUMN cusip_normalized SET NOT NULL,
    ALTER COLUMN cusip_valid SET NOT NULL,
    ALTER COLUMN quantity_fails SET NOT NULL,
    ALTER COLUMN reference_price_raw SET NOT NULL,
    ALTER COLUMN quality_status SET NOT NULL,
    ALTER COLUMN identity_status SET NOT NULL,
    ALTER COLUMN source_file SET NOT NULL,
    ALTER COLUMN source_member SET NOT NULL,
    ALTER COLUMN source_row_number SET NOT NULL,
    ADD PRIMARY KEY (source_file, source_member, source_row_number),
    ADD FOREIGN KEY (security_id) REFERENCES market_structure.security_identity;

CREATE INDEX ftd_daily_security_date_idx
    ON market_structure.ftd_daily (security_id, settlement_date)
    WHERE security_id IS NOT NULL;
CREATE INDEX ftd_daily_date_brin
    ON market_structure.ftd_daily USING brin (settlement_date);
