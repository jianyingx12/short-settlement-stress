ALTER TABLE market_structure.ftd_analysis
    ALTER COLUMN security_id SET NOT NULL,
    ALTER COLUMN settlement_date SET NOT NULL,
    ALTER COLUMN cusip SET NOT NULL,
    ALTER COLUMN ftd_mapping_confidence SET NOT NULL,
    ALTER COLUMN fails_quantity SET NOT NULL,
    ALTER COLUMN is_primary_analysis_period SET NOT NULL,
    ALTER COLUMN prior_ftd_observation_count SET NOT NULL,
    ALTER COLUMN prior_14d_short_volume_observation_count SET NOT NULL,
    ALTER COLUMN ftd_cohort SET NOT NULL,
    ADD PRIMARY KEY (security_id, settlement_date),
    ADD CHECK (ftd_mapping_confidence IN ('HIGH', 'MEDIUM')),
    ADD CHECK (fails_quantity >= 0),
    ADD CHECK (reference_price IS NULL OR reference_price >= 0),
    ADD CHECK (ftd_value IS NULL OR ftd_value >= 0),
    ADD CHECK (prior_ftd_observation_count >= 0),
    ADD CHECK (prior_14d_short_volume_observation_count BETWEEN 0 AND 14),
    ADD CHECK (ftd_quantity_history_percentile_band IS NULL
        OR ftd_quantity_history_percentile_band BETWEEN 0 AND 1),
    ADD CHECK (prior_14d_short_volume_ratio_percentile IS NULL
        OR prior_14d_short_volume_ratio_percentile BETWEEN 0 AND 1),
    ADD CHECK (days_since_short_interest_settlement IS NULL
        OR days_since_short_interest_settlement >= 0);

CREATE INDEX ftd_analysis_settlement_date_brin
    ON market_structure.ftd_analysis USING brin (settlement_date);

ANALYZE market_structure.ftd_analysis;
