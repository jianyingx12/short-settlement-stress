SELECT *
FROM market_structure.cleaning_quality_summary
ORDER BY dataset;

SELECT *
FROM market_structure.identity_match_summary
ORDER BY dataset, identity_status, mapping_confidence, mapping_method;

SELECT *
FROM market_structure.identity_match_by_period
ORDER BY dataset, period, identity_status, mapping_confidence;

SELECT *
FROM market_structure.primary_short_interest_identity_summary
ORDER BY identity_status, mapping_confidence, mapping_method;

SELECT *
FROM market_structure.cleaning_null_summary
ORDER BY dataset, field_name;

SELECT *
FROM market_structure.cleaning_coverage_summary
ORDER BY dataset;

SELECT *
FROM market_structure.security_dataset_overlap;

SELECT *
FROM market_structure.high_confidence_security_overlap;

SELECT *
FROM market_structure.latest_complete_shared_month;
