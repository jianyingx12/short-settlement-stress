-- The rows are loaded by date, so BRIN keeps the date indexes small.
CREATE INDEX IF NOT EXISTS raw_short_volume_trade_date_brin
    ON market_structure.raw_short_volume USING brin (trade_date);
CREATE INDEX IF NOT EXISTS raw_short_interest_settlement_date_brin
    ON market_structure.raw_short_interest USING brin (settlement_date);
CREATE INDEX IF NOT EXISTS raw_ftd_settlement_date_brin
    ON market_structure.raw_ftd USING brin (settlement_date);

-- These support the symbol/date and CUSIP/date joins used later.
CREATE INDEX IF NOT EXISTS raw_short_volume_symbol_date_idx
    ON market_structure.raw_short_volume (symbol, trade_date);
CREATE INDEX IF NOT EXISTS raw_short_interest_symbol_date_idx
    ON market_structure.raw_short_interest (symbol_code, settlement_date);
CREATE INDEX IF NOT EXISTS raw_ftd_symbol_date_idx
    ON market_structure.raw_ftd (symbol, settlement_date);
CREATE INDEX IF NOT EXISTS raw_ftd_cusip_date_idx
    ON market_structure.raw_ftd (cusip, settlement_date);
