CREATE TABLE market_structure.bi_dashboard_metadata AS
SELECT
    1::smallint AS metadata_id,
    date '2018-08-01' AS analysis_start_date,
    (latest_complete_shared_month + INTERVAL '1 month - 1 day')::date
        AS analysis_end_date,
    'FINRA and SEC'::text AS data_sources
FROM market_structure.latest_complete_shared_month;

ALTER TABLE market_structure.bi_dashboard_metadata
    ADD PRIMARY KEY (metadata_id);

-- Reduce each market-wide metric to 20 fixed bins before Power BI imports it.
CREATE TABLE market_structure.bi_metric_distribution AS
WITH metric_values AS (
    SELECT
        'short_volume_ratio'::text AS metric,
        short_volume_ratio::double precision AS value
    FROM market_structure.short_volume_features
    WHERE is_primary_analysis_period

    UNION ALL

    SELECT
        'short_interest_percentile',
        short_interest_full_sample_percentile::double precision
    FROM market_structure.short_interest_cycles
    WHERE is_primary_analysis_period
      AND short_interest_full_sample_percentile IS NOT NULL

    UNION ALL

    SELECT
        'relative_ftd_intensity',
        ftd_quantity_history_percentile_band::double precision
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
      AND ftd_quantity_history_percentile_band IS NOT NULL
), binned AS (
    SELECT
        metric,
        least(19, greatest(0, floor(value * 20)::integer)) AS bin_order
    FROM metric_values
    WHERE value BETWEEN 0 AND 1
), counts AS (
    SELECT metric, bin_order, count(*)::bigint AS observation_count
    FROM binned
    GROUP BY metric, bin_order
)
SELECT
    metric,
    CASE metric
        WHEN 'short_volume_ratio' THEN 'Daily short-volume ratio'
        WHEN 'short_interest_percentile' THEN 'Short-interest historical percentile'
        WHEN 'relative_ftd_intensity' THEN 'Security-relative FTD intensity'
    END AS metric_label,
    bin_order,
    bin_order / 20.0 AS bin_lower,
    (bin_order + 1) / 20.0 AS bin_upper,
    observation_count,
    observation_count::double precision
        / sum(observation_count) OVER (PARTITION BY metric) AS observation_share
FROM counts;

ALTER TABLE market_structure.bi_metric_distribution
    ADD PRIMARY KEY (metric, bin_order);

CREATE VIEW market_structure.bi_statistical_results AS
SELECT
    research_question,
    analysis_name,
    sample,
    observation_count,
    estimate_name,
    estimate,
    confidence_low,
    confidence_high,
    effect_size_name,
    effect_size,
    method,
    notes
FROM market_structure.statistical_results;

-- These three values supply the relationship summary on the overview page.
CREATE TABLE market_structure.bi_key_relationships AS
WITH requested(display_order, relationship_key, relationship_label, analysis_name) AS (
    VALUES
        (1, 'short_activity_to_short_interest',
            'Recent short activity to short interest',
            'rq1_activity_vs_short_interest'),
        (2, 'relative_ftd_to_short_interest',
            'Relative FTD intensity to short interest',
            'rq3_relative_ftd_vs_short_interest'),
        (3, 'relative_ftd_to_short_activity',
            'Relative FTD intensity to prior short activity',
            'rq3_relative_ftd_vs_short_activity')
)
SELECT
    requested.display_order,
    requested.relationship_key,
    requested.relationship_label,
    result.research_question,
    result.observation_count,
    result.estimate AS spearman_correlation,
    result.confidence_low,
    result.confidence_high
FROM requested
JOIN market_structure.statistical_results AS result
    ON result.analysis_name = requested.analysis_name
   AND result.sample = 'primary_high_and_medium'
   AND result.estimate_name = 'spearman';

ALTER TABLE market_structure.bi_key_relationships
    ADD PRIMARY KEY (relationship_key);

-- Pull the dashboard's headline effect sizes from the formal results table.
CREATE TABLE market_structure.bi_key_effects AS
WITH requested(display_order, effect_key, effect_label, analysis_name) AS (
    VALUES
        (1, 'rq1_top_vs_bottom',
            'RQ1: top versus bottom activity decile',
            'rq1_top_vs_bottom_short_interest'),
        (2, 'rq2_extreme_change',
            'RQ2: extreme activity increase versus decrease',
            'rq2_extreme_increase_vs_decrease'),
        (3, 'rq4_peak_intensity',
            'Peak historical FTD intensity',
            'rq4_persistent_peak_intensity'),
        (4, 'rq4_peak_quantity',
            'Peak FTD quantity',
            'rq4_persistent_peak_quantity'),
        (5, 'rq4_prior_activity',
            'Prior short activity',
            'rq4_persistent_prior_short_activity'),
        (6, 'rq4_short_interest',
            'Short interest',
            'rq4_persistent_short_interest')
)
SELECT
    requested.display_order,
    requested.effect_key,
    requested.effect_label,
    result.research_question,
    result.observation_count,
    result.effect_size_name,
    result.effect_size
FROM requested
JOIN market_structure.statistical_results AS result
    ON result.analysis_name = requested.analysis_name
   AND result.sample = 'primary_high_and_medium'
   AND result.effect_size_name = 'cliffs_delta'
WHERE result.estimate_name LIKE 'median_difference%';

ALTER TABLE market_structure.bi_key_effects
    ADD PRIMARY KEY (effect_key);

-- Reuse Phase 8 cohort results and add the prior-activity medians needed for RQ3.
CREATE TABLE market_structure.bi_relationship_cohorts AS
WITH formal_cohorts AS (
    SELECT
        CASE research_question WHEN 'RQ1' THEN 1 WHEN 'RQ2' THEN 2 ELSE 3 END
            AS question_order,
        research_question,
        analysis_name,
        CASE analysis_name
            WHEN 'rq1_activity_cohorts' THEN 'Short-interest historical percentile'
            WHEN 'rq2_activity_change_cohorts' THEN 'Signed-log short-interest change'
            WHEN 'rq3_ftd_severity_cohorts' THEN 'Short-interest historical percentile'
        END AS metric_label,
        sample AS cohort,
        observation_count,
        estimate_name,
        estimate
    FROM market_structure.statistical_results
    WHERE analysis_name IN (
        'rq1_activity_cohorts',
        'rq2_activity_change_cohorts',
        'rq3_ftd_severity_cohorts'
    )
      AND estimate_name IN ('mean', 'median')
), ftd_activity AS (
    SELECT
        3 AS question_order,
        'RQ3'::text AS research_question,
        'rq3_ftd_severity_cohorts_prior_activity'::text AS analysis_name,
        'Prior short-volume percentile'::text AS metric_label,
        ftd_cohort AS cohort,
        count(*)::bigint AS observation_count,
        avg(prior_14d_short_volume_ratio_percentile)::double precision AS mean_value,
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY prior_14d_short_volume_ratio_percentile
        )::double precision AS median_value
    FROM market_structure.ftd_analysis
    WHERE is_primary_analysis_period
      AND ftd_cohort <> 'insufficient_history'
      AND prior_14d_short_volume_ratio_percentile IS NOT NULL
    GROUP BY ftd_cohort
), combined AS (
    SELECT * FROM formal_cohorts

    UNION ALL

    SELECT
        question_order,
        research_question,
        analysis_name,
        metric_label,
        cohort,
        observation_count,
        estimate.estimate_name,
        estimate.estimate
    FROM ftd_activity
    CROSS JOIN LATERAL (VALUES
        ('mean'::text, mean_value),
        ('median'::text, median_value)
    ) AS estimate(estimate_name, estimate)
)
SELECT
    question_order,
    research_question,
    analysis_name,
    metric_label,
    cohort,
    CASE cohort
        WHEN 'bottom_10' THEN 'Bottom 10%'
        WHEN '10_to_25' THEN '10% to 25%'
        WHEN '25_to_50' THEN '25% to 50%'
        WHEN '50_to_75' THEN '50% to 75%'
        WHEN '75_to_90' THEN '75% to 90%'
        WHEN 'top_10' THEN 'Top 10%'
        WHEN 'extreme_decrease' THEN 'Extreme decrease'
        WHEN 'moderate_decrease' THEN 'Moderate decrease'
        WHEN 'typical' THEN 'Typical'
        WHEN 'moderate_increase' THEN 'Moderate increase'
        WHEN 'extreme_increase' THEN 'Extreme increase'
        WHEN 'below_p95' THEN 'Below p95'
        WHEN 'p95_to_p99' THEN 'p95 to p99'
        WHEN 'p99_to_p995' THEN 'p99 to p99.5'
        WHEN 'p995_plus' THEN 'p99.5 and above'
    END AS cohort_label,
    CASE cohort
        WHEN 'bottom_10' THEN 1 WHEN 'extreme_decrease' THEN 1 WHEN 'below_p95' THEN 1
        WHEN '10_to_25' THEN 2 WHEN 'moderate_decrease' THEN 2 WHEN 'p95_to_p99' THEN 2
        WHEN '25_to_50' THEN 3 WHEN 'typical' THEN 3 WHEN 'p99_to_p995' THEN 3
        WHEN '50_to_75' THEN 4 WHEN 'moderate_increase' THEN 4 WHEN 'p995_plus' THEN 4
        WHEN '75_to_90' THEN 5 WHEN 'extreme_increase' THEN 5
        WHEN 'top_10' THEN 6
    END AS cohort_order,
    observation_count,
    estimate_name,
    estimate
FROM combined;

ALTER TABLE market_structure.bi_relationship_cohorts
    ADD PRIMARY KEY (analysis_name, cohort, estimate_name);

COMMENT ON TABLE market_structure.bi_metric_distribution IS
    'Small import table for the three market-wide distributions.';

COMMENT ON VIEW market_structure.bi_statistical_results IS
    'Formal estimates exposed without p-values for dashboard reporting.';
