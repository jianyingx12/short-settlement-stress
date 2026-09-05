SELECT
    count(*) FILTER (WHERE symbol IS NULL) AS blank_symbols_preserved,
    count(*) FILTER (WHERE cusip IS NULL) AS blank_cusips_preserved,
    count(*) FILTER (
        WHERE reference_price IS NULL AND btrim(reference_price_raw) NOT IN ('', '.')
    ) AS unparseable_prices_preserved,
    count(*) FILTER (WHERE reference_price_raw = '.') AS dot_prices_preserved
FROM market_structure.raw_ftd;

SELECT count(*) AS fractional_short_volume_rows
FROM market_structure.raw_short_volume
WHERE short_volume <> trunc(short_volume)
   OR short_exempt_volume <> trunc(short_exempt_volume)
   OR total_volume <> trunc(total_volume);

SELECT
    min(short_volume) AS min_short_volume,
    max(short_volume) AS max_short_volume,
    min(short_exempt_volume) AS min_short_exempt_volume,
    max(short_exempt_volume) AS max_short_exempt_volume,
    min(total_volume) AS min_total_volume,
    max(total_volume) AS max_total_volume
FROM market_structure.raw_short_volume;

SELECT
    count(*) FILTER (WHERE current_short_position_quantity IS NULL) AS missing_current_position,
    count(*) FILTER (WHERE previous_short_position_quantity IS NULL) AS missing_previous_position,
    count(*) FILTER (WHERE average_daily_volume_quantity IS NULL) AS missing_average_daily_volume,
    count(*) FILTER (WHERE days_to_cover_quantity IS NULL) AS missing_days_to_cover,
    min(current_short_position_quantity) AS min_current_position,
    max(current_short_position_quantity) AS max_current_position
FROM market_structure.raw_short_interest;

SELECT
    min(quantity_fails) AS min_fails_quantity,
    max(quantity_fails) AS max_fails_quantity,
    min(reference_price) AS min_parsed_price,
    max(reference_price) AS max_parsed_price
FROM market_structure.raw_ftd;

SELECT dataset, count(*) AS files_loaded, sum(rows_loaded) AS manifest_rows
FROM market_structure.ingestion_file
GROUP BY dataset
ORDER BY dataset;
