ALTER TABLE market_structure.short_volume_features
    ALTER COLUMN security_id SET NOT NULL,
    ALTER COLUMN trade_date SET NOT NULL,
    ALTER COLUMN symbol SET NOT NULL,
    ALTER COLUMN mapping_confidence SET NOT NULL,
    ALTER COLUMN short_volume SET NOT NULL,
    ALTER COLUMN short_exempt_volume SET NOT NULL,
    ALTER COLUMN total_volume SET NOT NULL,
    ALTER COLUMN short_volume_ratio SET NOT NULL,
    ALTER COLUMN short_exempt_ratio SET NOT NULL,
    ALTER COLUMN is_primary_analysis_period SET NOT NULL,
    ALTER COLUMN observation_number SET NOT NULL,
    ALTER COLUMN short_volume_ratio_daily_percentile SET NOT NULL,
    ADD PRIMARY KEY (security_id, trade_date),
    ADD CHECK (mapping_confidence IN ('HIGH', 'MEDIUM')),
    ADD CHECK (short_volume >= 0),
    ADD CHECK (short_exempt_volume >= 0),
    ADD CHECK (total_volume > 0),
    ADD CHECK (short_volume_ratio BETWEEN 0 AND 1),
    ADD CHECK (short_exempt_ratio BETWEEN 0 AND 1),
    ADD CHECK (
        short_exempt_share_of_short IS NULL
        OR short_exempt_share_of_short BETWEEN 0 AND 1
    ),
    ADD CHECK (short_volume_ratio_daily_percentile BETWEEN 0 AND 1);

-- Keep the date index small; validation queries mostly scan broad date ranges.
CREATE INDEX short_volume_features_trade_date_brin
    ON market_structure.short_volume_features USING brin (trade_date);

ANALYZE market_structure.short_volume_features;
