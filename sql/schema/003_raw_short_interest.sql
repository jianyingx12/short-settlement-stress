CREATE TABLE IF NOT EXISTS market_structure.raw_short_interest (
    accounting_year_month_number integer NOT NULL,
    symbol_code text NOT NULL CHECK (symbol_code <> ''),
    issue_name text,
    issuer_services_group_exchange_code text,
    market_class_code text,
    current_short_position_quantity numeric,
    previous_short_position_quantity numeric,
    stock_split_flag text,
    average_daily_volume_quantity numeric,
    days_to_cover_quantity numeric,
    revision_flag text,
    change_percent numeric,
    change_previous_number numeric,
    settlement_date date NOT NULL,
    source_file text NOT NULL,
    source_row_number integer NOT NULL CHECK (source_row_number >= 2),
    ingested_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (source_file, source_row_number),
    CHECK (current_short_position_quantity IS NULL OR current_short_position_quantity >= 0),
    CHECK (previous_short_position_quantity IS NULL OR previous_short_position_quantity >= 0),
    CHECK (average_daily_volume_quantity IS NULL OR average_daily_volume_quantity >= 0)
);

COMMENT ON COLUMN market_structure.raw_short_interest.accounting_year_month_number IS
    'Original FINRA YYYYMMDD value; settlement_date is stored separately.';
