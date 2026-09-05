DO $$
DECLARE
    expected_rows bigint;
    feature_rows bigint;
    invalid_rows bigint;
BEGIN
    SELECT count(*)
    INTO expected_rows
    FROM market_structure.short_volume_daily
    WHERE identity_status = 'MATCHED'
      AND mapping_confidence IN ('HIGH', 'MEDIUM')
      AND quality_status = 'VALID'
      AND security_id IS NOT NULL
      AND total_volume > 0;

    SELECT count(*)
    INTO feature_rows
    FROM market_structure.short_volume_features;

    ASSERT feature_rows = expected_rows,
        'feature population differs from the documented eligible population';

    SELECT count(*)
    INTO invalid_rows
    FROM market_structure.short_volume_features
    WHERE abs(short_volume_ratio - short_volume::double precision / total_volume) > 1e-12
       OR abs(short_exempt_ratio - short_exempt_volume::double precision / total_volume) > 1e-12
       OR (
            short_volume > 0
            AND abs(
                short_exempt_share_of_short
                - short_exempt_volume::double precision / short_volume
            ) > 1e-12
       )
       OR (short_volume = 0 AND short_exempt_share_of_short IS NOT NULL)
       OR (observation_number < 5 AND short_volume_ratio_avg_5d IS NOT NULL)
       OR (observation_number < 14 AND short_volume_ratio_avg_14d IS NOT NULL)
       OR (observation_number < 30 AND short_volume_ratio_avg_30d IS NOT NULL)
       OR (observation_number >= 5 AND short_volume_ratio_avg_5d IS NULL)
       OR (observation_number >= 14 AND short_volume_ratio_avg_14d IS NULL)
       OR (observation_number >= 30 AND short_volume_ratio_avg_30d IS NULL)
       OR (observation_number <= 20 AND short_volume_ratio_history_zscore IS NOT NULL);

    ASSERT invalid_rows = 0,
        'short-volume formulas or observation-window boundaries are invalid';
END;
$$;

DO $$
DECLARE
    cutoff_date date;
    invalid_flags bigint;
BEGIN
    SELECT (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
    INTO cutoff_date
    FROM market_structure.latest_complete_shared_month;

    SELECT count(*)
    INTO invalid_flags
    FROM market_structure.short_volume_features
    WHERE is_primary_analysis_period IS DISTINCT FROM (trade_date <= cutoff_date);

    ASSERT invalid_flags = 0,
        'primary-period flags do not match the frozen shared-month cutoff';
END;
$$;
