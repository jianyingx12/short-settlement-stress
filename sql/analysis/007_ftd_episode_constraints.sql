ALTER TABLE market_structure.ftd_episodes
    ALTER COLUMN episode_id SET NOT NULL,
    ALTER COLUMN security_id SET NOT NULL,
    ALTER COLUMN episode_number SET NOT NULL,
    ALTER COLUMN ftd_mapping_confidence SET NOT NULL,
    ALTER COLUMN episode_start_date SET NOT NULL,
    ALTER COLUMN episode_end_date SET NOT NULL,
    ALTER COLUMN duration_calendar_days SET NOT NULL,
    ALTER COLUMN observation_count SET NOT NULL,
    ALTER COLUMN episode_class SET NOT NULL,
    ALTER COLUMN duration_group SET NOT NULL,
    ALTER COLUMN max_fails_quantity SET NOT NULL,
    ALTER COLUMN median_fails_quantity SET NOT NULL,
    ALTER COLUMN ftd_balance_days SET NOT NULL,
    ALTER COLUMN peak_date SET NOT NULL,
    ALTER COLUMN priced_observation_count SET NOT NULL,
    ALTER COLUMN intensity_group SET NOT NULL,
    ALTER COLUMN is_left_censored SET NOT NULL,
    ALTER COLUMN is_right_censored SET NOT NULL,
    ALTER COLUMN crosses_primary_period_end SET NOT NULL,
    ALTER COLUMN is_primary_analysis_period SET NOT NULL,
    ADD PRIMARY KEY (episode_id),
    ADD UNIQUE (security_id, episode_start_date),
    ADD CHECK (episode_end_date >= episode_start_date),
    ADD CHECK (duration_calendar_days = episode_end_date - episode_start_date + 1),
    ADD CHECK (observation_count >= 1),
    ADD CHECK (
        (episode_class = 'isolated' AND observation_count = 1)
        OR (episode_class = 'persistent' AND observation_count >= 2)
    ),
    ADD CHECK (max_fails_quantity >= 0),
    ADD CHECK (ftd_balance_days >= max_fails_quantity),
    ADD CHECK (priced_observation_count BETWEEN 0 AND observation_count),
    ADD CHECK (peak_date BETWEEN episode_start_date AND episode_end_date),
    ADD CHECK (days_since_previous_episode IS NULL OR days_since_previous_episode > 0),
    ADD CHECK (days_until_next_episode IS NULL OR days_until_next_episode > 0);

ANALYZE market_structure.ftd_episodes;
