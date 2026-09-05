DO $$
DECLARE
    raw_count bigint;
    clean_count bigint;
BEGIN
    SELECT count(*) INTO raw_count FROM market_structure.raw_short_volume;
    SELECT count(*) INTO clean_count FROM market_structure.short_volume_daily;
    ASSERT raw_count = clean_count, 'short-volume row count changed during cleaning';

    SELECT count(*) INTO raw_count FROM market_structure.raw_short_interest;
    SELECT count(*) INTO clean_count FROM market_structure.short_interest_observation;
    ASSERT raw_count = clean_count, 'short-interest row count changed during cleaning';

    SELECT count(*) INTO raw_count FROM market_structure.raw_ftd;
    SELECT count(*) INTO clean_count FROM market_structure.ftd_daily;
    ASSERT raw_count = clean_count, 'FTD row count changed during cleaning';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.cleaning_duplicate_summary
        WHERE duplicate_rows > 0
    ), 'duplicate business keys require an explicit resolution rule';

    ASSERT (
        SELECT count(*)
        FROM market_structure.short_interest_observation
        WHERE is_revision
    ) = (
        SELECT count(*)
        FROM market_structure.raw_short_interest
        WHERE upper(btrim(coalesce(revision_flag, ''))) = 'R'
    ), 'short-interest revision flags were not preserved';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.ftd_daily
        WHERE symbol_missing AND symbol_raw IS NOT NULL
    ), 'blank FTD symbols were not preserved as NULL';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.ftd_daily
        WHERE reference_price_raw = '.' AND reference_price IS NOT NULL
    ), 'missing FTD prices were given numeric values';
END;
$$;
