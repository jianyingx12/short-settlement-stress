-- Population retained for feature engineering and identity-based exclusions.
SELECT
    count(*) AS total_cleaned_rows,
    count(*) FILTER (WHERE quality_status = 'VALID' AND total_volume > 0)
        AS valid_positive_volume_rows,
    count(*) FILTER (
        WHERE quality_status = 'VALID'
          AND total_volume > 0
          AND identity_status = 'MATCHED'
          AND mapping_confidence = 'HIGH'
    ) AS high_confidence_rows,
    count(*) FILTER (
        WHERE quality_status = 'VALID'
          AND total_volume > 0
          AND identity_status = 'MATCHED'
          AND mapping_confidence = 'MEDIUM'
    ) AS medium_confidence_rows,
    count(*) FILTER (
        WHERE quality_status = 'VALID'
          AND total_volume > 0
          AND identity_status = 'AMBIGUOUS'
    ) AS ambiguous_rows,
    count(*) FILTER (
        WHERE quality_status = 'VALID'
          AND total_volume > 0
          AND identity_status = 'UNRESOLVED'
    ) AS unresolved_rows,
    count(*) FILTER (
        WHERE quality_status <> 'VALID'
           OR total_volume IS NULL
           OR total_volume <= 0
    ) AS invalid_denominator_or_quality_rows
FROM market_structure.short_volume_daily;

-- Feature coverage, including rows retained outside the frozen primary period.
SELECT
    count(*) AS feature_rows,
    count(DISTINCT security_id) AS securities,
    min(trade_date) AS first_trade_date,
    max(trade_date) AS last_trade_date,
    count(*) FILTER (WHERE is_primary_analysis_period) AS primary_period_rows,
    count(*) FILTER (WHERE NOT is_primary_analysis_period) AS partial_period_rows,
    count(*) FILTER (WHERE short_volume_ratio_avg_5d IS NOT NULL) AS ready_5d_rows,
    count(*) FILTER (WHERE short_volume_ratio_avg_14d IS NOT NULL) AS ready_14d_rows,
    count(*) FILTER (WHERE short_volume_ratio_avg_30d IS NOT NULL) AS ready_30d_rows,
    count(*) FILTER (WHERE short_volume_ratio_history_zscore IS NOT NULL)
        AS ready_history_rows
FROM market_structure.short_volume_features;

-- Core metric distributions. Percentiles use the complete feature population.
SELECT
    count(*) AS observations,
    avg(short_volume_ratio) AS mean,
    stddev_samp(short_volume_ratio) AS standard_deviation,
    min(short_volume_ratio) AS minimum,
    percentile_cont(ARRAY[0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99])
        WITHIN GROUP (ORDER BY short_volume_ratio) AS percentiles,
    max(short_volume_ratio) AS maximum
FROM market_structure.short_volume_features;

SELECT
    feature_name,
    count(value) AS observations,
    avg(value) AS mean,
    stddev_samp(value) AS standard_deviation,
    min(value) AS minimum,
    percentile_cont(ARRAY[0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99])
        WITHIN GROUP (ORDER BY value) AS percentiles,
    max(value) AS maximum
FROM (
    SELECT 'rolling_average_5d' AS feature_name, short_volume_ratio_avg_5d AS value
    FROM market_structure.short_volume_features
    UNION ALL
    SELECT 'rolling_average_14d', short_volume_ratio_avg_14d
    FROM market_structure.short_volume_features
    UNION ALL
    SELECT 'rolling_average_30d', short_volume_ratio_avg_30d
    FROM market_structure.short_volume_features
    UNION ALL
    SELECT 'history_zscore', short_volume_ratio_history_zscore
    FROM market_structure.short_volume_features
    UNION ALL
    SELECT 'daily_percentile', short_volume_ratio_daily_percentile
    FROM market_structure.short_volume_features
) AS distributions
GROUP BY feature_name
ORDER BY feature_name;

-- Inspect extreme values with their denominators visible.
(SELECT 'highest_ratio' AS extreme_type, security_id, trade_date, symbol,
        short_volume, short_exempt_volume, total_volume, short_volume_ratio,
        short_volume_ratio_history_zscore
 FROM market_structure.short_volume_features
 ORDER BY short_volume_ratio DESC, total_volume DESC
 LIMIT 20)
UNION ALL
(SELECT 'highest_abs_history_zscore', security_id, trade_date, symbol,
        short_volume, short_exempt_volume, total_volume, short_volume_ratio,
        short_volume_ratio_history_zscore
 FROM market_structure.short_volume_features
 WHERE short_volume_ratio_history_zscore IS NOT NULL
 ORDER BY abs(short_volume_ratio_history_zscore) DESC
 LIMIT 20);

SELECT
    pg_size_pretty(pg_relation_size('market_structure.short_volume_features'))
        AS table_size,
    pg_size_pretty(pg_indexes_size('market_structure.short_volume_features'))
        AS index_size,
    pg_size_pretty(pg_total_relation_size('market_structure.short_volume_features'))
        AS total_size;
