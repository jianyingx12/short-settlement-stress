ALTER TABLE market_structure.short_interest_cycles
    ALTER COLUMN security_id SET NOT NULL,
    ALTER COLUMN settlement_date SET NOT NULL,
    ALTER COLUMN symbol SET NOT NULL,
    ALTER COLUMN short_interest_mapping_confidence SET NOT NULL,
    ALTER COLUMN current_short_position SET NOT NULL,
    ALTER COLUMN reported_previous_short_position SET NOT NULL,
    ALTER COLUMN average_daily_volume SET NOT NULL,
    ALTER COLUMN reported_days_to_cover SET NOT NULL,
    ALTER COLUMN is_revision SET NOT NULL,
    ALTER COLUMN has_stock_split SET NOT NULL,
    ALTER COLUMN is_primary_analysis_period SET NOT NULL,
    ALTER COLUMN is_consecutive_cycle SET NOT NULL,
    ALTER COLUMN prior_14d_observation_count SET NOT NULL,
    ADD PRIMARY KEY (security_id, settlement_date),
    ADD CHECK (short_interest_mapping_confidence IN ('HIGH', 'MEDIUM')),
    ADD CHECK (current_short_position >= 0),
    ADD CHECK (reported_previous_short_position >= 0),
    ADD CHECK (average_daily_volume >= 0),
    ADD CHECK (prior_14d_observation_count BETWEEN 0 AND 14),
    ADD CHECK (prior_14d_short_volume_ratio_avg IS NULL
        OR prior_14d_short_volume_ratio_avg BETWEEN 0 AND 1),
    ADD CHECK (short_interest_full_sample_percentile IS NULL
        OR short_interest_full_sample_percentile BETWEEN 0 AND 1),
    ADD CHECK (prior_14d_short_volume_ratio_percentile IS NULL
        OR prior_14d_short_volume_ratio_percentile BETWEEN 0 AND 1),
    ADD CHECK (prior_14d_activity_change_percentile IS NULL
        OR prior_14d_activity_change_percentile BETWEEN 0 AND 1);

CREATE INDEX short_interest_cycles_settlement_date_brin
    ON market_structure.short_interest_cycles USING brin (settlement_date);

ANALYZE market_structure.short_interest_cycles;
