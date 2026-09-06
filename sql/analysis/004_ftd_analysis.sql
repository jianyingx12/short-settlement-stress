CREATE TABLE market_structure.ftd_analysis AS
-- Keep later partial data, but mark it outside the shared primary period.
WITH cutoff AS (
    SELECT
        (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
            AS primary_analysis_end
    FROM market_structure.latest_complete_shared_month
), eligible AS (
    -- FTD identity is CUSIP-based; blank SEC symbols remain null.
    SELECT
        ftd.security_id,
        ftd.settlement_date,
        ftd.symbol_raw AS symbol,
        ftd.cusip_normalized AS cusip,
        ftd.mapping_confidence AS ftd_mapping_confidence,
        ftd.quantity_fails AS fails_quantity,
        ftd.reference_price,
        CASE
            WHEN ftd.reference_price IS NOT NULL THEN
                ftd.quantity_fails::numeric * ftd.reference_price
        END AS ftd_value,
        ftd.settlement_date <= cutoff.primary_analysis_end
            AS is_primary_analysis_period,
        row_number() OVER (
            PARTITION BY ftd.security_id
            ORDER BY ftd.settlement_date
        ) AS observation_number
    FROM market_structure.ftd_daily AS ftd
    CROSS JOIN cutoff
    WHERE ftd.quality_status = 'VALID'
      AND ftd.identity_status = 'MATCHED'
      AND ftd.mapping_confidence IN ('HIGH', 'MEDIUM')
      AND ftd.security_id IS NOT NULL
), historical_context AS (
    -- Band midpoints are coarse historical context, not exact percentiles.
    SELECT
        eligible.*,
        (observation_number - 1)::integer AS prior_ftd_observation_count,
        CASE WHEN observation_number > 200 THEN
            CASE
                WHEN fails_quantity < baseline.quantity_percentiles[1] THEN 0.005
                WHEN fails_quantity < baseline.quantity_percentiles[2] THEN 0.030
                WHEN fails_quantity < baseline.quantity_percentiles[3] THEN 0.075
                WHEN fails_quantity < baseline.quantity_percentiles[4] THEN 0.175
                WHEN fails_quantity < baseline.quantity_percentiles[5] THEN 0.375
                WHEN fails_quantity < baseline.quantity_percentiles[6] THEN 0.625
                WHEN fails_quantity < baseline.quantity_percentiles[7] THEN 0.825
                WHEN fails_quantity < baseline.quantity_percentiles[8] THEN 0.925
                WHEN fails_quantity < baseline.quantity_percentiles[9] THEN 0.970
                WHEN fails_quantity < baseline.quantity_percentiles[10] THEN 0.9925
                ELSE 0.9975
            END
        END AS ftd_quantity_history_percentile_band,
        CASE WHEN observation_number > 200
            THEN fails_quantity >= baseline.quantity_percentiles[8]
        END AS exceeds_baseline_p95,
        CASE WHEN observation_number > 200
            THEN fails_quantity >= baseline.quantity_percentiles[9]
        END AS exceeds_baseline_p99,
        CASE WHEN observation_number > 200
            THEN fails_quantity >= baseline.quantity_percentiles[10]
        END AS exceeds_baseline_p995
    FROM eligible
    JOIN market_structure.ftd_baseline AS baseline USING (security_id)
), aligned AS (
    -- Short volume is strictly earlier; short interest is latest on or before.
    SELECT
        history.*,
        volume.trade_date AS prior_short_volume_trade_date,
        CASE
            WHEN volume.observation_number >= 14 THEN 14
            ELSE coalesce(volume.observation_number, 0)
        END::smallint AS prior_14d_short_volume_observation_count,
        volume.mapping_confidence AS short_volume_mapping_confidence,
        volume.short_volume_ratio_avg_14d AS prior_14d_short_volume_ratio_avg,
        volume.short_volume_ratio_trend_14d AS prior_14d_short_volume_ratio_trend,
        interest.settlement_date AS aligned_short_interest_settlement_date,
        history.settlement_date - interest.settlement_date
            AS days_since_short_interest_settlement,
        interest.short_interest_mapping_confidence,
        interest.current_short_position,
        interest.days_to_cover,
        interest.percentage_short_interest_change,
        interest.signed_log_short_interest_change,
        interest.short_interest_full_sample_percentile
    FROM historical_context AS history
    LEFT JOIN LATERAL (
        SELECT feature.*
        FROM market_structure.short_volume_features AS feature
        WHERE feature.security_id = history.security_id
          AND feature.trade_date < history.settlement_date
        ORDER BY feature.trade_date DESC
        LIMIT 1
    ) AS volume ON true
    LEFT JOIN LATERAL (
        SELECT cycle.*
        FROM market_structure.short_interest_cycles AS cycle
        WHERE cycle.security_id = history.security_id
          AND cycle.settlement_date <= history.settlement_date
        ORDER BY cycle.settlement_date DESC
        LIMIT 1
    ) AS interest ON true
), activity_ranks AS (
    -- Compare recent activity only with securities on the same FTD date.
    SELECT
        security_id,
        settlement_date,
        rank() OVER daily_distribution AS value_rank,
        count(*) OVER (
            PARTITION BY settlement_date, prior_14d_short_volume_ratio_avg
        ) AS tie_count,
        count(*) OVER (PARTITION BY settlement_date) AS daily_count
    FROM aligned
    WHERE is_primary_analysis_period
      AND prior_14d_short_volume_ratio_avg IS NOT NULL
    WINDOW daily_distribution AS (
        PARTITION BY settlement_date
        ORDER BY prior_14d_short_volume_ratio_avg
    )
), prepared AS (
    SELECT
        aligned.*,
        CASE
            WHEN activity_ranks.daily_count = 1 THEN 0.5
            WHEN activity_ranks.daily_count > 1 THEN (
                activity_ranks.value_rank - 1
                    + (activity_ranks.tie_count - 1) / 2.0
            ) / (activity_ranks.daily_count - 1)
        END AS prior_14d_short_volume_ratio_percentile
    FROM aligned
    LEFT JOIN activity_ranks USING (security_id, settlement_date)
)
SELECT
    security_id,
    settlement_date,
    symbol,
    cusip,
    ftd_mapping_confidence,
    fails_quantity,
    reference_price,
    ftd_value,
    is_primary_analysis_period,
    prior_ftd_observation_count,
    ftd_quantity_history_percentile_band,
    exceeds_baseline_p95,
    exceeds_baseline_p99,
    exceeds_baseline_p995,
    CASE
        WHEN exceeds_baseline_p95 IS NULL THEN 'insufficient_history'
        WHEN exceeds_baseline_p995 THEN 'p995_plus'
        WHEN exceeds_baseline_p99 THEN 'p99_to_p995'
        WHEN exceeds_baseline_p95 THEN 'p95_to_p99'
        ELSE 'below_p95'
    END AS ftd_cohort,
    prior_short_volume_trade_date,
    prior_14d_short_volume_observation_count,
    short_volume_mapping_confidence,
    prior_14d_short_volume_ratio_avg,
    prior_14d_short_volume_ratio_trend,
    prior_14d_short_volume_ratio_percentile,
    aligned_short_interest_settlement_date,
    days_since_short_interest_settlement,
    short_interest_mapping_confidence,
    current_short_position,
    days_to_cover,
    percentage_short_interest_change,
    signed_log_short_interest_change,
    short_interest_full_sample_percentile,
    -- High context uses fixed 90th-percentile boundaries.
    CASE
        WHEN exceeds_baseline_p99
         AND short_interest_full_sample_percentile IS NOT NULL
         AND prior_14d_short_volume_ratio_percentile IS NOT NULL THEN concat(
            'high_ftd_',
            CASE WHEN short_interest_full_sample_percentile >= 0.90
                THEN 'high_si_' ELSE 'lower_si_' END,
            CASE WHEN prior_14d_short_volume_ratio_percentile >= 0.90
                THEN 'high_activity' ELSE 'normal_activity' END
        )
    END AS extreme_ftd_regime
FROM prepared;

COMMENT ON TABLE market_structure.ftd_analysis IS
    'Daily outstanding FTD balances with prior short-volume and settlement-date short-interest context. No FTD episodes are constructed.';

COMMENT ON COLUMN market_structure.ftd_analysis.ftd_value IS
    'Approximate notional value: fails quantity times the SEC prior-close reference price.';

COMMENT ON COLUMN market_structure.ftd_analysis.ftd_quantity_history_percentile_band IS
    'Coarse percentile band against the security''s first 200 FTD observations. Available only after that prior calibration period.';
