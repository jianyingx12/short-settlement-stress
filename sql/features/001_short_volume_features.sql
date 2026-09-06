CREATE TABLE market_structure.short_volume_features AS
-- Stop the primary sample at the latest month complete across all three sources.
WITH cutoff AS (
    SELECT
        (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
            AS primary_analysis_end
    FROM market_structure.latest_complete_shared_month
), daily AS (
    -- Keep rows with a usable identity and a positive volume denominator.
    SELECT
        volume.security_id,
        volume.trade_date,
        volume.symbol_raw AS symbol,
        volume.mapping_confidence,
        volume.short_volume,
        volume.short_exempt_volume,
        volume.total_volume,
        volume.short_volume::double precision
            / volume.total_volume::double precision AS short_volume_ratio,
        volume.short_exempt_volume::double precision
            / volume.total_volume::double precision AS short_exempt_ratio,
        CASE
            WHEN volume.short_volume > 0 THEN
                volume.short_exempt_volume::double precision
                    / volume.short_volume::double precision
        END AS short_exempt_share_of_short,
        cutoff.primary_analysis_end IS NOT NULL
            AND volume.trade_date <= cutoff.primary_analysis_end
            AS is_primary_analysis_period
    FROM market_structure.short_volume_daily AS volume
    CROSS JOIN cutoff
    WHERE volume.identity_status = 'MATCHED'
      AND volume.mapping_confidence IN ('HIGH', 'MEDIUM')
      AND volume.quality_status = 'VALID'
      AND volume.security_id IS NOT NULL
      AND volume.total_volume > 0
), numbered AS (
    -- Windows are based on trading observations, not calendar days.
    SELECT
        daily.*,
        row_number() OVER security_history AS observation_number,
        lag(short_volume_ratio) OVER security_history AS previous_short_volume_ratio,
        lag(short_volume_ratio, 14) OVER security_history AS short_volume_ratio_lag_14d
    FROM daily
    WINDOW security_history AS (
        PARTITION BY security_id
        ORDER BY trade_date
    )
), windowed AS (
    -- Historical averages exclude the current row; rolling averages include it.
    SELECT
        numbered.*,
        avg(short_volume_ratio) OVER window_5d AS avg_5d_raw,
        avg(short_volume_ratio) OVER window_14d AS avg_14d_raw,
        avg(short_volume_ratio) OVER window_30d AS avg_30d_raw,
        stddev_samp(short_volume_ratio) OVER window_5d AS std_5d_raw,
        stddev_samp(short_volume_ratio) OVER window_14d AS std_14d_raw,
        stddev_samp(short_volume_ratio) OVER window_30d AS std_30d_raw,
        avg(short_volume_ratio) OVER prior_14d_block AS prior_14d_avg_raw,
        max(short_volume_ratio) OVER prior_14d AS prior_14d_max_raw,
        regr_slope(
            short_volume_ratio,
            observation_number::double precision
        ) OVER window_14d AS trend_14d_raw,
        avg(short_volume_ratio) OVER prior_history AS history_mean,
        stddev_samp(short_volume_ratio) OVER prior_history AS history_std,
        rank() OVER daily_distribution AS daily_ratio_rank,
        count(*) OVER (
            PARTITION BY trade_date, short_volume_ratio
        ) AS daily_ratio_ties,
        count(*) OVER (
            PARTITION BY trade_date
        ) AS daily_security_count
    FROM numbered
    WINDOW
        window_5d AS (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
        ),
        window_14d AS (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
        ),
        window_30d AS (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ),
        prior_14d_block AS (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS BETWEEN 27 PRECEDING AND 14 PRECEDING
        ),
        prior_14d AS (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING
        ),
        prior_history AS (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        daily_distribution AS (
            PARTITION BY trade_date
            ORDER BY short_volume_ratio
        )
)
-- Do not publish a rolling value until its full window is available.
SELECT
    security_id,
    trade_date,
    symbol,
    mapping_confidence,
    short_volume,
    short_exempt_volume,
    total_volume,
    short_volume_ratio,
    short_exempt_ratio,
    short_exempt_share_of_short,
    is_primary_analysis_period,
    observation_number,
    CASE WHEN observation_number >= 5 THEN avg_5d_raw END AS short_volume_ratio_avg_5d,
    CASE WHEN observation_number >= 14 THEN avg_14d_raw END AS short_volume_ratio_avg_14d,
    CASE WHEN observation_number >= 30 THEN avg_30d_raw END AS short_volume_ratio_avg_30d,
    CASE WHEN observation_number >= 5 THEN std_5d_raw END AS short_volume_ratio_std_5d,
    CASE WHEN observation_number >= 14 THEN std_14d_raw END AS short_volume_ratio_std_14d,
    CASE WHEN observation_number >= 30 THEN std_30d_raw END AS short_volume_ratio_std_30d,
    CASE
        WHEN previous_short_volume_ratio IS NOT NULL
            THEN short_volume_ratio - previous_short_volume_ratio
    END AS short_volume_ratio_change_1d,
    CASE
        WHEN short_volume_ratio_lag_14d IS NOT NULL
            THEN short_volume_ratio - short_volume_ratio_lag_14d
    END AS short_volume_ratio_change_14d,
    CASE
        WHEN observation_number >= 15 THEN prior_14d_max_raw
    END AS short_volume_ratio_prior_14d_max,
    CASE
        WHEN observation_number >= 14 THEN trend_14d_raw
    END AS short_volume_ratio_trend_14d,
    CASE
        WHEN observation_number >= 30
            THEN avg_5d_raw - avg_30d_raw
    END AS short_volume_ratio_avg_5d_minus_30d,
    CASE
        WHEN observation_number >= 28
            THEN avg_14d_raw - prior_14d_avg_raw
    END AS short_volume_ratio_avg_14d_change,
    -- Require 20 earlier observations before measuring historical deviation.
    CASE
        WHEN observation_number >= 21 AND history_std > 0
            THEN (short_volume_ratio - history_mean) / history_std
    END AS short_volume_ratio_history_zscore,
    -- Rank each ratio against other supported securities from the same date.
    CASE
        WHEN daily_security_count = 1 THEN 0.5
        ELSE (
            daily_ratio_rank - 1 + (daily_ratio_ties - 1) / 2.0
        ) / (daily_security_count - 1)
    END AS short_volume_ratio_daily_percentile
FROM windowed;

COMMENT ON TABLE market_structure.short_volume_features IS
    'One supported security per trade date with short-volume features based only on current and earlier observations.';

COMMENT ON COLUMN market_structure.short_volume_features.short_volume_ratio IS
    'FINRA ShortVolume / TotalVolume. ShortVolume already includes short-exempt volume.';

COMMENT ON COLUMN market_structure.short_volume_features.short_volume_ratio_daily_percentile IS
    'Exact average-rank percentile among supported securities on the same trade date.';
