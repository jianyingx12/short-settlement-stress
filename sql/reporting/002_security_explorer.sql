-- Keep the slicer keyed by security_id; the symbol is display text only.
CREATE TABLE market_structure.bi_security_catalog AS
SELECT
    identity.security_id,
    identity.cusip_normalized AS cusip,
    latest_symbol.example_source_symbol AS display_symbol,
    concat(
        coalesce(latest_symbol.example_source_symbol, 'No symbol'),
        ' | ', identity.cusip_normalized,
        ' | ID ', identity.security_id
    ) AS security_label,
    identity.issuer_name_match_key,
    identity.first_seen,
    identity.last_seen,
    coalesce(symbol_count.symbol_count, 0)::integer AS historical_symbol_count
FROM market_structure.security_identity AS identity
LEFT JOIN LATERAL (
    SELECT history.example_source_symbol
    FROM market_structure.security_symbol_history AS history
    WHERE history.security_id = identity.security_id
    ORDER BY
        history.last_seen DESC,
        history.observation_count DESC,
        history.example_source_symbol
    LIMIT 1
) AS latest_symbol ON true
LEFT JOIN LATERAL (
    SELECT count(*) AS symbol_count
    FROM market_structure.security_symbol_history AS history
    WHERE history.security_id = identity.security_id
) AS symbol_count ON true;

ALTER TABLE market_structure.bi_security_catalog
    ADD PRIMARY KEY (security_id);

CREATE VIEW market_structure.bi_security_short_interest AS
SELECT
    security_id,
    settlement_date,
    symbol AS source_symbol,
    short_interest_mapping_confidence AS identity_confidence,
    current_short_position,
    short_interest_full_sample_percentile AS short_interest_percentile,
    signed_log_short_interest_change,
    days_to_cover,
    is_revision,
    has_stock_split,
    prior_14d_last_trade_date,
    prior_14d_short_volume_ratio_avg,
    prior_14d_short_volume_ratio_percentile
FROM market_structure.short_interest_cycles
WHERE is_primary_analysis_period;

CREATE VIEW market_structure.bi_security_short_volume AS
SELECT
    security_id,
    trade_date,
    symbol AS source_symbol,
    mapping_confidence AS identity_confidence,
    short_volume,
    total_volume,
    short_volume_ratio,
    short_volume_ratio_avg_14d,
    short_volume_ratio_daily_percentile AS activity_percentile,
    short_volume_ratio_trend_14d AS activity_trend
FROM market_structure.short_volume_features
WHERE is_primary_analysis_period;

CREATE VIEW market_structure.bi_security_ftd AS
SELECT
    security_id,
    settlement_date,
    symbol AS source_symbol,
    ftd_mapping_confidence AS identity_confidence,
    fails_quantity,
    reference_price,
    ftd_value,
    ftd_quantity_history_percentile_band AS relative_ftd_intensity,
    ftd_cohort,
    exceeds_baseline_p95,
    exceeds_baseline_p99,
    exceeds_baseline_p995,
    prior_short_volume_trade_date,
    aligned_short_interest_settlement_date,
    days_since_short_interest_settlement
FROM market_structure.ftd_analysis
WHERE is_primary_analysis_period;

COMMENT ON TABLE market_structure.bi_security_catalog IS
    'Security slicer labels keyed by CUSIP-based security_id, never ticker alone.';

COMMENT ON VIEW market_structure.bi_security_short_interest IS
    'Primary-period short-interest timeline for filtered DirectQuery use.';

COMMENT ON VIEW market_structure.bi_security_short_volume IS
    'Primary-period short-volume timeline for filtered DirectQuery use.';

COMMENT ON VIEW market_structure.bi_security_ftd IS
    'Primary-period FTD timeline for filtered DirectQuery use; missing values stay null.';
