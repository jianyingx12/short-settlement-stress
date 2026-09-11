DO $$
DECLARE
    invalid_rows bigint;
    expected_rows bigint;
    primary_end_date date;
    reported_rows bigint;
BEGIN
    SELECT (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
    INTO primary_end_date
    FROM market_structure.latest_complete_shared_month;

    ASSERT (SELECT count(*) FROM market_structure.statistical_results) > 0,
        'statistical results table is empty';

    ASSERT (
        SELECT count(DISTINCT research_question)
        FROM market_structure.statistical_results
    ) = 4, 'not all research questions have results';

    SELECT count(*)
    INTO invalid_rows
    FROM market_structure.statistical_results
    WHERE observation_count <= 0
       OR confidence_low > confidence_high
       OR p_value < 0
       OR p_value > 1;

    ASSERT invalid_rows = 0,
        'statistical result bounds or sample sizes are invalid';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.short_interest_cycles
        WHERE is_primary_analysis_period
          AND settlement_date > primary_end_date
    ), 'partial short-interest rows entered the primary sample';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.ftd_analysis
        WHERE is_primary_analysis_period
          AND settlement_date > primary_end_date
    ), 'partial FTD rows entered the primary sample';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.ftd_episodes
        WHERE is_primary_analysis_period
          AND episode_end_date > primary_end_date
    ), 'partial episodes entered the primary sample';

    SELECT count(*)
    INTO expected_rows
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
      AND prior_14d_short_volume_ratio_avg IS NOT NULL
      AND short_interest_full_sample_percentile IS NOT NULL;

    SELECT observation_count
    INTO reported_rows
    FROM market_structure.statistical_results
    WHERE analysis_name = 'rq1_activity_vs_short_interest'
      AND estimate_name = 'spearman';

    ASSERT reported_rows = expected_rows, 'RQ1 primary sample does not reconcile';

    SELECT count(*)
    INTO expected_rows
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
      AND prior_14d_short_volume_ratio_avg_change IS NOT NULL
      AND signed_log_short_interest_change IS NOT NULL;

    SELECT observation_count
    INTO reported_rows
    FROM market_structure.statistical_results
    WHERE analysis_name = 'rq2_activity_change_vs_short_interest_change'
      AND estimate_name = 'spearman';

    ASSERT reported_rows = expected_rows, 'RQ2 primary sample does not reconcile';

    SELECT count(*)
    INTO expected_rows
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
      AND ftd_quantity_history_percentile_band IS NOT NULL
      AND short_interest_full_sample_percentile IS NOT NULL;

    SELECT observation_count
    INTO reported_rows
    FROM market_structure.statistical_results
    WHERE analysis_name = 'rq3_relative_ftd_vs_short_interest'
      AND estimate_name = 'spearman';

    ASSERT reported_rows = expected_rows, 'RQ3 primary sample does not reconcile';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.short_interest_cycles
        WHERE short_volume_cohort IS DISTINCT FROM CASE
            WHEN prior_14d_short_volume_ratio_percentile < 0.10 THEN 'bottom_10'
            WHEN prior_14d_short_volume_ratio_percentile < 0.25 THEN '10_to_25'
            WHEN prior_14d_short_volume_ratio_percentile < 0.50 THEN '25_to_50'
            WHEN prior_14d_short_volume_ratio_percentile < 0.75 THEN '50_to_75'
            WHEN prior_14d_short_volume_ratio_percentile < 0.90 THEN '75_to_90'
            WHEN prior_14d_short_volume_ratio_percentile IS NOT NULL THEN 'top_10'
        END
    ), 'RQ1 cohort boundaries changed';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.short_interest_cycles
        WHERE prior_14d_last_trade_date >= settlement_date
    ), 'short-volume context includes a future date';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.ftd_analysis
        WHERE aligned_short_interest_settlement_date > settlement_date
           OR prior_short_volume_trade_date >= settlement_date
    ), 'FTD context includes a future date';

    ASSERT (
        SELECT observation_count
        FROM market_structure.statistical_results
        WHERE analysis_name = 'rq3_stale_alignment_sensitivity'
          AND sample = 'short_interest_age_30_days'
          AND estimate_name = 'spearman'
    ) <= (
        SELECT observation_count
        FROM market_structure.statistical_results
        WHERE analysis_name = 'rq3_stale_alignment_sensitivity'
          AND sample = 'full_alignment'
          AND estimate_name = 'spearman'
    ), 'fresh-alignment sensitivity is not nested in the full sample';
END;
$$;

SELECT
    research_question,
    count(*) AS results,
    min(observation_count) AS smallest_sample,
    max(observation_count) AS largest_sample
FROM market_structure.statistical_results
GROUP BY research_question
ORDER BY research_question;
