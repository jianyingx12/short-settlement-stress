CREATE TABLE IF NOT EXISTS market_structure.raw_ftd (
    settlement_date date NOT NULL,
    cusip text,
    symbol text,
    quantity_fails bigint NOT NULL CHECK (quantity_fails >= 0),
    description text,
    reference_price numeric,
    reference_price_raw text NOT NULL,
    source_file text NOT NULL,
    source_member text NOT NULL,
    source_row_number integer NOT NULL CHECK (source_row_number >= 2),
    ingested_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (source_file, source_member, source_row_number)
);

COMMENT ON COLUMN market_structure.raw_ftd.reference_price_raw IS
    'Original SEC PRICE text before numeric parsing.';

COMMENT ON COLUMN market_structure.raw_ftd.symbol IS
    'Nullable because valid SEC rows can have a blank symbol.';
