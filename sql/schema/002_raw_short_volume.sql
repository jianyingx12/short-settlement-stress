CREATE TABLE IF NOT EXISTS market_structure.raw_short_volume (
    trade_date date NOT NULL,
    symbol text NOT NULL CHECK (symbol <> ''),
    short_volume numeric NOT NULL CHECK (short_volume >= 0),
    short_exempt_volume numeric NOT NULL CHECK (short_exempt_volume >= 0),
    total_volume numeric NOT NULL CHECK (total_volume >= 0),
    market text NOT NULL,
    source_file text NOT NULL,
    source_row_number integer NOT NULL CHECK (source_row_number >= 2),
    ingested_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (source_file, source_row_number)
);

COMMENT ON COLUMN market_structure.raw_short_volume.short_volume IS
    'Uses NUMERIC because FINRA files can contain fractional shares.';
