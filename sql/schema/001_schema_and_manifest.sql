CREATE SCHEMA IF NOT EXISTS market_structure;

CREATE TABLE IF NOT EXISTS market_structure.ingestion_file (
    dataset text NOT NULL,
    source_file text NOT NULL,
    source_sha256 character(64) NOT NULL,
    source_bytes bigint NOT NULL CHECK (source_bytes >= 0),
    rows_loaded bigint NOT NULL CHECK (rows_loaded >= 0),
    loaded_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (dataset, source_file),
    CHECK (dataset IN ('finra_short_volume', 'finra_short_interest', 'sec_ftd')),
    CHECK (source_sha256 ~ '^[0-9a-f]{64}$')
);

COMMENT ON TABLE market_structure.ingestion_file IS
    'Tracks which source files have been loaded.';
