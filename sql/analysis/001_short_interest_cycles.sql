CREATE TABLE market_structure.short_interest_cycles AS
-- Stop the primary sample at the latest month complete across all three sources.
WITH cutoff AS (
    SELECT
        (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
            AS primary_analysis_end
    FROM market_structure.latest_complete_shared_month
), reporting_cycles AS (
    -- Number the shared settlement dates so a missing cycle can be detected later.
    SELECT
        settlement_date,
        dense_rank() OVER (ORDER BY settlement_date) AS reporting_cycle_number
    FROM (
        SELECT DISTINCT settlement_date
        FROM market_structure.short_interest_observation
    ) AS dates
), eligible AS (
    -- Keep observations with a usable security match and valid reported values.
    SELECT
        interest.security_id,
        interest.settlement_date,
        reporting_cycles.reporting_cycle_number,
        interest.symbol_raw AS symbol,
        interest.mapping_confidence AS short_interest_mapping_confidence,
        interest.current_short_position_quantity AS current_short_position,
        interest.previous_short_position_quantity AS reported_previous_short_position,
        interest.average_daily_volume_quantity AS average_daily_volume,
        interest.days_to_cover_quantity AS reported_days_to_cover,
        CASE
            WHEN interest.average_daily_volume_quantity > 0 THEN
                interest.current_short_position_quantity::double precision
                    / interest.average_daily_volume_quantity::double precision
        END AS days_to_cover,
        interest.is_revision,
        interest.has_stock_split,
        interest.settlement_date <= cutoff.primary_analysis_end
            AS is_primary_analysis_period
    FROM market_structure.short_interest_observation AS interest
    CROSS JOIN cutoff
    JOIN reporting_cycles USING (settlement_date)
    WHERE interest.primary_population
      AND interest.quality_status = 'VALID'
      AND interest.identity_status = 'MATCHED'
      AND interest.mapping_confidence IN ('HIGH', 'MEDIUM')
      AND interest.security_id IS NOT NULL
), sequence_context AS (
    -- Compare each security with its own earlier reporting history.
    SELECT
        eligible.*,
        lag(settlement_date) OVER security_cycles AS previous_settlement_date,
        lead(settlement_date) OVER security_cycles AS next_settlement_date,
        lag(reporting_cycle_number) OVER security_cycles
            AS previous_reporting_cycle_number,
        lag(current_short_position) OVER security_cycles AS previous_cycle_short_position,
        lag(days_to_cover) OVER security_cycles AS previous_cycle_days_to_cover,
        count(*) OVER prior_cycles AS prior_cycle_count,
        avg(current_short_position) OVER prior_cycles AS prior_position_mean,
        stddev_samp(current_short_position) OVER prior_cycles AS prior_position_std
    FROM eligible
    WINDOW
        security_cycles AS (
            PARTITION BY security_id
            ORDER BY settlement_date
        ),
        prior_cycles AS (
            PARTITION BY security_id
            ORDER BY settlement_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        )
), cycles AS (
    -- Changes are calculated only when the previous market-wide cycle is present.
    SELECT
        sequence_context.*,
        coalesce(
            reporting_cycle_number - previous_reporting_cycle_number = 1,
            false
        ) AS is_consecutive_cycle,
        CASE
            WHEN reporting_cycle_number - previous_reporting_cycle_number = 1
                THEN reported_previous_short_position = previous_cycle_short_position
        END AS reported_previous_matches_cycle,
        CASE
            WHEN reporting_cycle_number - previous_reporting_cycle_number = 1
                THEN current_short_position - previous_cycle_short_position
        END AS absolute_short_interest_change,
        CASE
            WHEN reporting_cycle_number - previous_reporting_cycle_number = 1
             AND previous_cycle_short_position > 0 THEN
                (current_short_position - previous_cycle_short_position)::double precision
                    / previous_cycle_short_position::double precision
        END AS percentage_short_interest_change,
        CASE
            WHEN reporting_cycle_number - previous_reporting_cycle_number = 1 THEN
                ln(1.0 + current_short_position::double precision)
                    - ln(1.0 + previous_cycle_short_position::double precision)
        END AS signed_log_short_interest_change,
        CASE
            WHEN reporting_cycle_number - previous_reporting_cycle_number = 1
             AND days_to_cover IS NOT NULL
             AND previous_cycle_days_to_cover IS NOT NULL
                THEN days_to_cover - previous_cycle_days_to_cover
        END AS days_to_cover_change,
        CASE
            WHEN prior_cycle_count >= 12 AND prior_position_std > 0 THEN
                (current_short_position - prior_position_mean)::double precision
                    / prior_position_std::double precision
        END AS short_interest_history_zscore
    FROM sequence_context
), aligned AS (
    -- Attach the latest 14 trading observations strictly before settlement.
    SELECT
        cycles.*,
        volume.last_trade_date AS prior_14d_last_trade_date,
        volume.first_trade_date AS prior_14d_first_trade_date,
        volume.observation_count AS prior_14d_observation_count,
        -- Leave the 14-day measures null when a complete window is unavailable.
        CASE WHEN volume.observation_count = 14 THEN volume.ratio_avg END
            AS prior_14d_short_volume_ratio_avg,
        CASE WHEN volume.observation_count = 14 THEN volume.ratio_max END
            AS prior_14d_short_volume_ratio_max,
        CASE WHEN volume.observation_count = 14 THEN volume.ratio_min END
            AS prior_14d_short_volume_ratio_min,
        CASE WHEN volume.observation_count = 14 THEN volume.ratio_std END
            AS prior_14d_short_volume_ratio_std,
        CASE WHEN volume.observation_count = 14 THEN volume.ratio_change END
            AS prior_14d_short_volume_ratio_change,
        CASE WHEN volume.observation_count = 14 THEN volume.ratio_trend END
            AS prior_14d_short_volume_ratio_trend,
        CASE WHEN volume.observation_count = 14 THEN volume.daily_percentile_avg END
            AS prior_14d_daily_percentile_avg,
        CASE WHEN volume.observation_count = 14 THEN volume.short_exempt_ratio_avg END
            AS prior_14d_short_exempt_ratio_avg,
        CASE WHEN volume.observation_count = 14 THEN volume.total_volume_avg END
            AS prior_14d_total_volume_avg,
        CASE WHEN volume.observation_count = 14 THEN volume.total_volume_min END
            AS prior_14d_total_volume_min,
        CASE WHEN volume.observation_count = 14 THEN volume.all_high_confidence END
            AS prior_14d_all_high_confidence,
        volume.anchor_avg_5d AS prior_5d_short_volume_ratio_avg,
        volume.anchor_avg_30d AS prior_30d_short_volume_ratio_avg,
        volume.anchor_history_zscore AS prior_trade_date_history_zscore
    FROM cycles
    LEFT JOIN LATERAL (
        SELECT
            max(trade_date) AS last_trade_date,
            min(trade_date) AS first_trade_date,
            count(*)::smallint AS observation_count,
            avg(short_volume_ratio) AS ratio_avg,
            max(short_volume_ratio) AS ratio_max,
            min(short_volume_ratio) AS ratio_min,
            stddev_samp(short_volume_ratio) AS ratio_std,
            max(short_volume_ratio) FILTER (WHERE recent_rank = 1)
                - max(short_volume_ratio) FILTER (WHERE recent_rank = 14)
                AS ratio_change,
            regr_slope(short_volume_ratio, observation_number::double precision)
                AS ratio_trend,
            avg(short_volume_ratio_daily_percentile) AS daily_percentile_avg,
            avg(short_exempt_ratio) AS short_exempt_ratio_avg,
            avg(total_volume::double precision) AS total_volume_avg,
            min(total_volume) AS total_volume_min,
            bool_and(mapping_confidence = 'HIGH') AS all_high_confidence,
            max(short_volume_ratio_avg_5d) FILTER (WHERE recent_rank = 1)
                AS anchor_avg_5d,
            max(short_volume_ratio_avg_30d) FILTER (WHERE recent_rank = 1)
                AS anchor_avg_30d,
            max(short_volume_ratio_history_zscore) FILTER (WHERE recent_rank = 1)
                AS anchor_history_zscore
        FROM (
            SELECT
                recent.*,
                row_number() OVER (ORDER BY trade_date DESC) AS recent_rank
            FROM (
                SELECT
                    feature.trade_date,
                    feature.mapping_confidence,
                    feature.observation_number,
                    feature.short_volume_ratio,
                    feature.short_exempt_ratio,
                    feature.total_volume,
                    feature.short_volume_ratio_avg_5d,
                    feature.short_volume_ratio_avg_30d,
                    feature.short_volume_ratio_history_zscore,
                    feature.short_volume_ratio_daily_percentile
                FROM market_structure.short_volume_features AS feature
                WHERE feature.security_id = cycles.security_id
                  AND feature.trade_date < cycles.settlement_date
                ORDER BY feature.trade_date DESC
                LIMIT 14
            ) AS recent
        ) AS numbered_recent
    ) AS volume ON true
), activity_context AS (
    SELECT
        aligned.*,
        lag(prior_14d_short_volume_ratio_avg) OVER security_cycles
            AS previous_cycle_prior_14d_ratio_avg
    FROM aligned
    WINDOW security_cycles AS (
        PARTITION BY security_id
        ORDER BY settlement_date
    )
), analysis_base AS (
    SELECT
        activity_context.*,
        CASE
            WHEN is_consecutive_cycle
             AND prior_14d_short_volume_ratio_avg IS NOT NULL
             AND previous_cycle_prior_14d_ratio_avg IS NOT NULL THEN
                prior_14d_short_volume_ratio_avg
                    - previous_cycle_prior_14d_ratio_avg
        END AS prior_14d_short_volume_ratio_avg_change
    FROM activity_context
), short_interest_ranks AS (
    -- This rank uses each security's full primary-period history and is descriptive.
    SELECT
        security_id,
        settlement_date,
        rank() OVER security_distribution AS value_rank,
        count(*) OVER (PARTITION BY security_id, current_short_position) AS tie_count,
        count(*) OVER (PARTITION BY security_id) AS security_count
    FROM analysis_base
    WHERE is_primary_analysis_period
    WINDOW security_distribution AS (
        PARTITION BY security_id
        ORDER BY current_short_position
    )
), volume_ranks AS (
    -- Volume ranks compare securities within the same settlement cycle.
    SELECT
        security_id,
        settlement_date,
        rank() OVER cycle_distribution AS value_rank,
        count(*) OVER (
            PARTITION BY settlement_date, prior_14d_short_volume_ratio_avg
        ) AS tie_count,
        count(*) OVER (PARTITION BY settlement_date) AS cycle_count
    FROM analysis_base
    WHERE is_primary_analysis_period
      AND prior_14d_short_volume_ratio_avg IS NOT NULL
    WINDOW cycle_distribution AS (
        PARTITION BY settlement_date
        ORDER BY prior_14d_short_volume_ratio_avg
    )
), activity_change_ranks AS (
    SELECT
        security_id,
        settlement_date,
        rank() OVER cycle_distribution AS value_rank,
        count(*) OVER (
            PARTITION BY settlement_date, prior_14d_short_volume_ratio_avg_change
        ) AS tie_count,
        count(*) OVER (PARTITION BY settlement_date) AS cycle_count
    FROM analysis_base
    WHERE is_primary_analysis_period
      AND prior_14d_short_volume_ratio_avg_change IS NOT NULL
    WINDOW cycle_distribution AS (
        PARTITION BY settlement_date
        ORDER BY prior_14d_short_volume_ratio_avg_change
    )
), ranked AS (
    SELECT
        analysis_base.*,
        CASE
            WHEN short_interest_ranks.security_count = 1 THEN 0.5
            WHEN short_interest_ranks.security_count > 1 THEN (
                short_interest_ranks.value_rank - 1
                    + (short_interest_ranks.tie_count - 1) / 2.0
            ) / (short_interest_ranks.security_count - 1)
        END AS short_interest_full_sample_percentile,
        CASE
            WHEN volume_ranks.cycle_count = 1 THEN 0.5
            WHEN volume_ranks.cycle_count > 1 THEN (
                volume_ranks.value_rank - 1
                    + (volume_ranks.tie_count - 1) / 2.0
            ) / (volume_ranks.cycle_count - 1)
        END AS prior_14d_short_volume_ratio_percentile,
        CASE
            WHEN activity_change_ranks.cycle_count = 1 THEN 0.5
            WHEN activity_change_ranks.cycle_count > 1 THEN (
                activity_change_ranks.value_rank - 1
                    + (activity_change_ranks.tie_count - 1) / 2.0
            ) / (activity_change_ranks.cycle_count - 1)
        END AS prior_14d_activity_change_percentile
    FROM analysis_base
    LEFT JOIN short_interest_ranks USING (security_id, settlement_date)
    LEFT JOIN volume_ranks USING (security_id, settlement_date)
    LEFT JOIN activity_change_ranks USING (security_id, settlement_date)
)
SELECT
    security_id,
    settlement_date,
    symbol,
    short_interest_mapping_confidence,
    current_short_position,
    reported_previous_short_position,
    previous_cycle_short_position,
    average_daily_volume,
    reported_days_to_cover,
    days_to_cover,
    is_revision,
    has_stock_split,
    is_primary_analysis_period,
    previous_settlement_date,
    next_settlement_date,
    is_consecutive_cycle,
    reported_previous_matches_cycle,
    absolute_short_interest_change,
    percentage_short_interest_change,
    signed_log_short_interest_change,
    days_to_cover_change,
    short_interest_history_zscore,
    short_interest_full_sample_percentile,
    prior_14d_first_trade_date,
    prior_14d_last_trade_date,
    prior_14d_observation_count,
    prior_14d_short_volume_ratio_avg,
    prior_14d_short_volume_ratio_max,
    prior_14d_short_volume_ratio_min,
    prior_14d_short_volume_ratio_std,
    prior_14d_short_volume_ratio_change,
    prior_14d_short_volume_ratio_trend,
    prior_14d_daily_percentile_avg,
    prior_14d_short_exempt_ratio_avg,
    prior_14d_total_volume_avg,
    prior_14d_total_volume_min,
    prior_14d_all_high_confidence,
    prior_5d_short_volume_ratio_avg,
    prior_30d_short_volume_ratio_avg,
    prior_trade_date_history_zscore,
    prior_14d_short_volume_ratio_avg_change,
    prior_14d_short_volume_ratio_percentile,
    prior_14d_activity_change_percentile,
    CASE
        WHEN prior_14d_short_volume_ratio_percentile < 0.10 THEN 'bottom_10'
        WHEN prior_14d_short_volume_ratio_percentile < 0.25 THEN '10_to_25'
        WHEN prior_14d_short_volume_ratio_percentile < 0.50 THEN '25_to_50'
        WHEN prior_14d_short_volume_ratio_percentile < 0.75 THEN '50_to_75'
        WHEN prior_14d_short_volume_ratio_percentile < 0.90 THEN '75_to_90'
        WHEN prior_14d_short_volume_ratio_percentile IS NOT NULL THEN 'top_10'
    END AS short_volume_cohort,
    CASE
        WHEN prior_14d_activity_change_percentile < 0.10 THEN 'extreme_decrease'
        WHEN prior_14d_activity_change_percentile < 0.25 THEN 'moderate_decrease'
        WHEN prior_14d_activity_change_percentile < 0.75 THEN 'typical'
        WHEN prior_14d_activity_change_percentile < 0.90 THEN 'moderate_increase'
        WHEN prior_14d_activity_change_percentile IS NOT NULL THEN 'extreme_increase'
    END AS activity_change_cohort
FROM ranked;

COMMENT ON TABLE market_structure.short_interest_cycles IS
    'Exchange-listed short-interest cycles aligned to FINRA observations strictly before settlement. Publication dates remain unavailable.';

COMMENT ON COLUMN market_structure.short_interest_cycles.short_interest_full_sample_percentile IS
    'Ex-post within-security average-rank percentile over the complete primary period; it is not an as-of feature.';

COMMENT ON COLUMN market_structure.short_interest_cycles.prior_14d_short_volume_ratio_percentile IS
    'Average-rank percentile of the prior-14 mean among securities on the same settlement date.';
