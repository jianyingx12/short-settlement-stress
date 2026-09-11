DO $$
DECLARE
    import_row_count bigint;
    primary_end_date date;
BEGIN
    SELECT (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
    INTO primary_end_date
    FROM market_structure.latest_complete_shared_month;

    ASSERT (
        SELECT analysis_end_date = primary_end_date
        FROM market_structure.bi_dashboard_metadata
    ), 'dashboard cutoff does not match the complete shared period';

    ASSERT NOT EXISTS (
        SELECT 1 FROM market_structure.bi_security_short_interest
        WHERE settlement_date > primary_end_date
    ), 'short-interest explorer includes partial data';

    ASSERT NOT EXISTS (
        SELECT 1 FROM market_structure.bi_security_short_volume
        WHERE trade_date > primary_end_date
    ), 'short-volume explorer includes partial data';

    ASSERT NOT EXISTS (
        SELECT 1 FROM market_structure.bi_security_ftd
        WHERE settlement_date > primary_end_date
    ), 'FTD explorer includes partial data';

    ASSERT (
        SELECT count(*) FROM market_structure.bi_statistical_results
    ) = (
        SELECT count(*) FROM market_structure.statistical_results
    ), 'dashboard statistical results do not reconcile';

    ASSERT (
        SELECT count(*) FROM market_structure.bi_key_relationships
    ) = 3, 'overview relationship summary is incomplete';

    ASSERT (
        SELECT count(*) FROM market_structure.bi_key_effects
    ) = 6, 'headline effect-size summary is incomplete';

    ASSERT (
        SELECT count(*) FROM market_structure.bi_ftd_regime_summary
    ) = 4, 'p99 FTD regime summary is incomplete';

    ASSERT abs((
        SELECT sum(observation_share)
        FROM market_structure.bi_ftd_regime_summary
    ) - 1.0) < 0.000000001, 'p99 FTD regime shares do not sum to one';

    ASSERT (
        SELECT sum(episode_count)
        FROM market_structure.bi_ftd_episode_distribution
    ) = (
        SELECT count(*)
        FROM market_structure.ftd_episodes
        WHERE is_primary_analysis_period
          AND NOT is_left_censored
    ), 'episode distribution does not reconcile';

    ASSERT (
        SELECT count(*) FROM market_structure.bi_security_ftd
        WHERE ftd_value IS NULL
    ) = (
        SELECT count(*) FROM market_structure.ftd_analysis
        WHERE is_primary_analysis_period
          AND ftd_value IS NULL
    ), 'missing FTD values were not preserved';

    SELECT sum(row_count)
    INTO import_row_count
    FROM (
        SELECT count(*) AS row_count FROM market_structure.bi_dashboard_metadata
        UNION ALL SELECT count(*) FROM market_structure.bi_security_catalog
        UNION ALL SELECT count(*) FROM market_structure.bi_metric_distribution
        UNION ALL SELECT count(*) FROM market_structure.bi_key_relationships
        UNION ALL SELECT count(*) FROM market_structure.bi_key_effects
        UNION ALL SELECT count(*) FROM market_structure.bi_relationship_cohorts
        UNION ALL SELECT count(*) FROM market_structure.bi_ftd_episode_distribution
        UNION ALL SELECT count(*) FROM market_structure.bi_ftd_episode_comparison
        UNION ALL SELECT count(*) FROM market_structure.bi_ftd_duration_severity
        UNION ALL SELECT count(*) FROM market_structure.bi_ftd_recurrence
        UNION ALL SELECT count(*) FROM market_structure.bi_ftd_regime_summary
        UNION ALL SELECT count(*) FROM market_structure.bi_statistical_results
    ) AS import_tables;

    ASSERT import_row_count < 100000,
        'Power BI import layer is unexpectedly large';
END;
$$;

SELECT
    'import_layer_rows' AS check_name,
    sum(row_count) AS check_value
FROM (
    SELECT count(*) AS row_count FROM market_structure.bi_dashboard_metadata
    UNION ALL SELECT count(*) FROM market_structure.bi_security_catalog
    UNION ALL SELECT count(*) FROM market_structure.bi_metric_distribution
    UNION ALL SELECT count(*) FROM market_structure.bi_key_relationships
    UNION ALL SELECT count(*) FROM market_structure.bi_key_effects
    UNION ALL SELECT count(*) FROM market_structure.bi_relationship_cohorts
    UNION ALL SELECT count(*) FROM market_structure.bi_ftd_episode_distribution
    UNION ALL SELECT count(*) FROM market_structure.bi_ftd_episode_comparison
    UNION ALL SELECT count(*) FROM market_structure.bi_ftd_duration_severity
    UNION ALL SELECT count(*) FROM market_structure.bi_ftd_recurrence
    UNION ALL SELECT count(*) FROM market_structure.bi_ftd_regime_summary
    UNION ALL SELECT count(*) FROM market_structure.bi_statistical_results
) AS import_tables;
