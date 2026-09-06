DO $$
DECLARE
    expected_rows bigint;
    cycle_rows bigint;
    expected_revisions bigint;
    cycle_revisions bigint;
    invalid_rows bigint;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE is_revision)
    INTO expected_rows, expected_revisions
    FROM market_structure.short_interest_observation
    WHERE primary_population
      AND quality_status = 'VALID'
      AND identity_status = 'MATCHED'
      AND mapping_confidence IN ('HIGH', 'MEDIUM')
      AND security_id IS NOT NULL;

    SELECT count(*), count(*) FILTER (WHERE is_revision)
    INTO cycle_rows, cycle_revisions
    FROM market_structure.short_interest_cycles;

    ASSERT cycle_rows = expected_rows,
        'short-interest cycle population differs from eligible source rows';
    ASSERT cycle_revisions = expected_revisions,
        'revision-marked rows were not preserved';

    SELECT count(*)
    INTO invalid_rows
    FROM market_structure.short_interest_cycles
    WHERE (average_daily_volume = 0 AND days_to_cover IS NOT NULL)
       OR (average_daily_volume > 0 AND abs(
            days_to_cover
                - current_short_position::double precision
                    / average_daily_volume::double precision
       ) > 1e-12)
       OR (previous_cycle_short_position = 0
            AND percentage_short_interest_change IS NOT NULL)
       OR (NOT is_consecutive_cycle AND absolute_short_interest_change IS NOT NULL)
       OR (is_consecutive_cycle AND absolute_short_interest_change
            <> current_short_position - previous_cycle_short_position)
       OR (prior_14d_observation_count = 14
            AND prior_14d_last_trade_date >= settlement_date)
       OR (prior_14d_observation_count = 14
            AND prior_14d_first_trade_date > prior_14d_last_trade_date)
       OR (prior_14d_observation_count < 14
            AND prior_14d_short_volume_ratio_avg IS NOT NULL)
       OR (prior_14d_observation_count = 14
            AND prior_14d_short_volume_ratio_avg IS NULL)
       OR (NOT is_primary_analysis_period
            AND (short_volume_cohort IS NOT NULL
              OR activity_change_cohort IS NOT NULL
              OR short_interest_full_sample_percentile IS NOT NULL))
       OR (short_volume_cohort = 'bottom_10'
            AND prior_14d_short_volume_ratio_percentile >= 0.10)
       OR (short_volume_cohort = 'top_10'
            AND prior_14d_short_volume_ratio_percentile < 0.90)
       OR (activity_change_cohort = 'extreme_decrease'
            AND prior_14d_activity_change_percentile >= 0.10)
       OR (activity_change_cohort = 'extreme_increase'
            AND prior_14d_activity_change_percentile < 0.90);

    ASSERT invalid_rows = 0,
        'short-interest changes, timing, or cohort boundaries are invalid';
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
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period IS DISTINCT FROM (settlement_date <= cutoff_date);

    ASSERT invalid_flags = 0,
        'short-interest primary-period flags do not match the shared cutoff';
END;
$$;
