SELECT source_file, source_row_number, count(*) AS copies
FROM market_structure.raw_short_volume
GROUP BY source_file, source_row_number
HAVING count(*) > 1;

SELECT source_file, source_row_number, count(*) AS copies
FROM market_structure.raw_short_interest
GROUP BY source_file, source_row_number
HAVING count(*) > 1;

SELECT source_file, source_member, source_row_number, count(*) AS copies
FROM market_structure.raw_ftd
GROUP BY source_file, source_member, source_row_number
HAVING count(*) > 1;
