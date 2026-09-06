DO $$
DECLARE
    expected_rows bigint;
    analysis_rows bigint;
    invalid_rows bigint;
BEGIN
    SELECT count(*)
    INTO expected_rows
    FROM market_structure.ftd_daily
    WHERE quality_status = 'VALID'
      AND identity_status = 'MATCHED'
      AND mapping_confidence IN ('HIGH', 'MEDIUM')
      AND security_id IS NOT NULL;

    SELECT count(*)
    INTO analysis_rows
    FROM market_structure.ftd_analysis;

    ASSERT analysis_rows = expected_rows,
        'FTD analysis population differs from the eligible source population';

    SELECT count(*)
    INTO invalid_rows
    FROM market_structure.ftd_analysis AS analysis
    JOIN market_structure.ftd_baseline AS baseline USING (security_id)
    WHERE (reference_price IS NULL) IS DISTINCT FROM (ftd_value IS NULL)
       OR (reference_price IS NOT NULL
            AND ftd_value <> fails_quantity::numeric * reference_price)
       OR (prior_ftd_observation_count < 200 AND (
            ftd_quantity_history_percentile_band IS NOT NULL
            OR exceeds_baseline_p95 IS NOT NULL
            OR exceeds_baseline_p99 IS NOT NULL
            OR exceeds_baseline_p995 IS NOT NULL
       ))
       OR (prior_ftd_observation_count >= 200 AND (
            ftd_quantity_history_percentile_band IS NULL
            OR exceeds_baseline_p95 IS NULL
            OR exceeds_baseline_p99 IS NULL
            OR exceeds_baseline_p995 IS NULL
       ))
       OR exceeds_baseline_p95 IS DISTINCT FROM (
            CASE WHEN prior_ftd_observation_count >= 200
                THEN fails_quantity >= baseline.quantity_percentiles[8] END
       )
       OR exceeds_baseline_p99 IS DISTINCT FROM (
            CASE WHEN prior_ftd_observation_count >= 200
                THEN fails_quantity >= baseline.quantity_percentiles[9] END
       )
       OR exceeds_baseline_p995 IS DISTINCT FROM (
            CASE WHEN prior_ftd_observation_count >= 200
                THEN fails_quantity >= baseline.quantity_percentiles[10] END
       )
       OR (prior_short_volume_trade_date IS NOT NULL
            AND prior_short_volume_trade_date >= settlement_date)
       OR (prior_14d_short_volume_observation_count < 14
            AND prior_14d_short_volume_ratio_avg IS NOT NULL)
       OR (prior_14d_short_volume_observation_count = 14
            AND prior_14d_short_volume_ratio_avg IS NULL)
       OR (aligned_short_interest_settlement_date IS NOT NULL
            AND aligned_short_interest_settlement_date > settlement_date)
       OR days_since_short_interest_settlement IS DISTINCT FROM
            settlement_date - aligned_short_interest_settlement_date;

    ASSERT invalid_rows = 0,
        'FTD values, history thresholds, or temporal alignments are invalid';
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
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period IS DISTINCT FROM
        (settlement_date <= cutoff_date);

    ASSERT invalid_flags = 0,
        'FTD primary-period flags do not match the shared cutoff';
END;
$$;
