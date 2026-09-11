from __future__ import annotations

import argparse
from pathlib import Path

from src.loading.common import read_database_settings
from src.sql_runner import run_sql_files
from src.statistics.analysis import Analysis
from src.statistics.methods import cliffs_delta


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = PROJECT_ROOT / "sql" / "statistics"


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the formal statistical analysis.")
    parser.add_argument("--env-file", type=Path, default=PROJECT_ROOT / ".env")
    args = parser.parse_args()

    run_sql_files([SQL_DIR / "001_results_table.sql"], args.env_file)

    import psycopg

    settings = read_database_settings(args.env_file)
    with psycopg.connect(**settings, autocommit=True) as connection:
        analysis = Analysis(connection)
        cycles = "market_structure.short_interest_cycles"
        ftd = "market_structure.ftd_analysis"
        episodes = "market_structure.ftd_episodes"
        primary_cycles = "is_primary_analysis_period"
        primary_ftd = "is_primary_analysis_period"
        primary_episodes = "is_primary_analysis_period AND NOT is_left_censored"

        # RQ1 compares prior short activity with the next short-interest report.
        analysis.analyze_pair(
            "RQ1", "rq1_activity_vs_short_interest", cycles,
            "prior_14d_short_volume_ratio_avg", "short_interest_full_sample_percentile",
            primary_cycles, within=True,
        )
        analysis.analyze_groups(
            "RQ1", "rq1_activity_cohorts", cycles, "short_volume_cohort",
            "short_interest_full_sample_percentile", primary_cycles,
        )
        analysis.analyze_groups(
            "RQ1", "rq1_activity_cohorts_days_to_cover", cycles,
            "short_volume_cohort", "days_to_cover", primary_cycles,
        )
        extreme_activity = (
            "is_primary_analysis_period AND short_volume_cohort "
            "IN ('bottom_10', 'top_10')"
        )
        analysis.analyze_binary(
            "RQ1", "rq1_top_vs_bottom_short_interest", cycles,
            "short_volume_cohort = 'top_10'",
            "short_interest_full_sample_percentile", extreme_activity,
        )
        analysis.analyze_binary(
            "RQ1", "rq1_top_vs_bottom_days_to_cover", cycles,
            "short_volume_cohort = 'top_10'", "days_to_cover", extreme_activity,
        )
        for window, value in (
            ("5_observations", "prior_5d_short_volume_ratio_avg"),
            ("30_observations", "prior_30d_short_volume_ratio_avg"),
        ):
            analysis.simple_pair(
                "RQ1", "rq1_window_sensitivity", cycles, value,
                "short_interest_full_sample_percentile", primary_cycles, window,
            )

        # RQ2 compares changes in short activity with changes in short interest.
        analysis.analyze_pair(
            "RQ2", "rq2_activity_change_vs_short_interest_change", cycles,
            "prior_14d_short_volume_ratio_avg_change", "signed_log_short_interest_change",
            primary_cycles, within=True,
        )
        analysis.analyze_groups(
            "RQ2", "rq2_activity_change_cohorts", cycles, "activity_change_cohort",
            "signed_log_short_interest_change", primary_cycles,
        )
        extreme_change = (
            "is_primary_analysis_period AND activity_change_cohort "
            "IN ('extreme_decrease', 'extreme_increase')"
        )
        analysis.analyze_binary(
            "RQ2", "rq2_extreme_increase_vs_decrease", cycles,
            "activity_change_cohort = 'extreme_increase'",
            "signed_log_short_interest_change", extreme_change,
        )
        analysis.simple_pair(
            "RQ2", "rq2_percentage_change_sensitivity", cycles,
            "prior_14d_short_volume_ratio_avg_change", "percentage_short_interest_change",
            primary_cycles, "unstable_percentage_change",
        )
        analysis.simple_pair(
            "RQ2", "rq2_absolute_change_sensitivity", cycles,
            "prior_14d_short_volume_ratio_avg_change", "absolute_short_interest_change",
            primary_cycles, "absolute_share_change",
        )

        # Remove the least liquid observations and repeat the main relationships.
        volume_cutoff = (
            "(SELECT percentile_cont(0.1) WITHIN GROUP "
            "(ORDER BY prior_14d_total_volume_avg) FROM "
            "market_structure.short_interest_cycles WHERE is_primary_analysis_period "
            "AND prior_14d_total_volume_avg IS NOT NULL)"
        )
        liquid_cycles = (
            f"is_primary_analysis_period AND prior_14d_total_volume_avg >= {volume_cutoff}"
        )
        analysis.simple_pair(
            "RQ1", "rq1_low_volume_sensitivity", cycles,
            "prior_14d_short_volume_ratio_avg", "short_interest_full_sample_percentile",
            liquid_cycles, "exclude_bottom_volume_decile",
        )
        analysis.simple_pair(
            "RQ2", "rq2_low_volume_sensitivity", cycles,
            "prior_14d_short_volume_ratio_avg_change", "signed_log_short_interest_change",
            liquid_cycles, "exclude_bottom_volume_decile",
        )

        # RQ3 checks whether unusually large FTD balances coincide with short interest.
        analysis.analyze_pair(
            "RQ3", "rq3_relative_ftd_vs_short_interest", ftd,
            "ftd_quantity_history_percentile_band", "short_interest_full_sample_percentile",
            primary_ftd,
        )
        analysis.analyze_pair(
            "RQ3", "rq3_relative_ftd_vs_short_activity", ftd,
            "ftd_quantity_history_percentile_band",
            "prior_14d_short_volume_ratio_percentile", primary_ftd,
        )
        analysis.simple_pair(
            "RQ3", "rq3_raw_ftd_sensitivity", ftd,
            "fails_quantity", "short_interest_full_sample_percentile",
            primary_ftd, "raw_quantity",
        )
        analysis.analyze_groups(
            "RQ3", "rq3_ftd_severity_cohorts", ftd, "ftd_cohort",
            "short_interest_full_sample_percentile",
            "is_primary_analysis_period AND ftd_cohort <> 'insufficient_history'",
        )
        for threshold, column in (
            ("p95", "exceeds_baseline_p95"),
            ("p99", "exceeds_baseline_p99"),
            ("p995", "exceeds_baseline_p995"),
        ):
            for context_name, value in (
                ("short_interest", "short_interest_full_sample_percentile"),
                ("short_activity", "prior_14d_short_volume_ratio_percentile"),
            ):
                analysis.analyze_binary(
                    "RQ3", f"rq3_{threshold}_{context_name}", ftd, column, value,
                    primary_ftd,
                )

        # RQ4 compares isolated FTD records with persistent FTD episodes.
        for context_name, value in (
            ("peak_intensity", "peak_ftd_history_percentile_band"),
            ("peak_quantity", "max_fails_quantity"),
            ("balance_days", "ftd_balance_days"),
            ("short_interest", "short_interest_full_sample_percentile"),
            ("prior_short_activity", "prior_14d_short_volume_ratio_percentile"),
            ("prior_activity_trend", "prior_14d_short_volume_ratio_trend"),
        ):
            analysis.analyze_binary(
                "RQ4", f"rq4_persistent_{context_name}", episodes,
                "episode_class = 'persistent'", value, primary_episodes,
            )

        # Repeat the analysis with stricter identity and alignment requirements.
        high_cycles = (
            "is_primary_analysis_period AND short_interest_mapping_confidence = 'HIGH' "
            "AND prior_14d_all_high_confidence"
        )
        analysis.simple_pair(
            "RQ1", "rq1_identity_sensitivity", cycles,
            "prior_14d_short_volume_ratio_avg", "short_interest_full_sample_percentile",
            high_cycles, "high_only",
        )

        high_ftd = (
            "is_primary_analysis_period AND ftd_mapping_confidence = 'HIGH' "
            "AND short_volume_mapping_confidence = 'HIGH' "
            "AND short_interest_mapping_confidence = 'HIGH'"
        )
        analysis.simple_pair(
            "RQ3", "rq3_identity_sensitivity", ftd,
            "ftd_quantity_history_percentile_band",
            "short_interest_full_sample_percentile", high_ftd, "high_only",
        )
        high_episodes = (
            f"{primary_episodes} AND ftd_mapping_confidence = 'HIGH' "
            "AND short_volume_mapping_confidence = 'HIGH' "
            "AND short_interest_mapping_confidence = 'HIGH'"
        )
        for context_name, value in (
            ("short_interest", "short_interest_full_sample_percentile"),
            ("short_activity", "prior_14d_short_volume_ratio_percentile"),
        ):
            analysis.analyze_binary(
                "RQ4", f"rq4_identity_{context_name}", episodes,
                "episode_class = 'persistent'", value, high_episodes, "high_only",
            )
        analysis.simple_pair(
            "RQ2", "rq2_identity_sensitivity", cycles,
            "prior_14d_short_volume_ratio_avg_change", "signed_log_short_interest_change",
            high_cycles, "high_only",
        )

        for sample, extra_filter in (
            ("full_alignment", "TRUE"),
            ("short_interest_age_30_days", "days_since_short_interest_settlement <= 30"),
        ):
            analysis.simple_pair(
                "RQ3", "rq3_stale_alignment_sensitivity", ftd,
                "ftd_quantity_history_percentile_band",
                "short_interest_full_sample_percentile",
                f"is_primary_analysis_period AND {extra_filter}", sample,
            )
            analysis.analyze_binary(
                "RQ4", "rq4_stale_alignment_sensitivity", episodes,
                "episode_class = 'persistent'", "short_interest_full_sample_percentile",
                f"{primary_episodes} AND {extra_filter}", sample,
            )

        # Period splits show whether effect direction is stable over time.
        analysis.analyze_periods(
            "RQ1", "rq1_period_robustness", cycles, "settlement_date",
            "prior_14d_short_volume_ratio_avg", "short_interest_full_sample_percentile",
            primary_cycles,
        )
        analysis.analyze_periods(
            "RQ2", "rq2_period_robustness", cycles, "settlement_date",
            "prior_14d_short_volume_ratio_avg_change", "signed_log_short_interest_change",
            primary_cycles,
        )
        analysis.analyze_periods(
            "RQ3", "rq3_period_robustness", ftd, "settlement_date",
            "ftd_quantity_history_percentile_band",
            "short_interest_full_sample_percentile", primary_ftd,
        )

        # Allow one missing SEC date when grouping FTD records into episodes.
        gap_rows = analysis.query(
            (SQL_DIR / "003_episode_gap_effects.sql").read_text(encoding="utf-8")
        )
        for metric in {str(row[0]) for row in gap_rows}:
            metric_rows = [row for row in gap_rows if row[0] == metric]
            by_group = {bool(row[1]): row for row in metric_rows}
            false_row, true_row = by_group[False], by_group[True]
            delta = cliffs_delta(
                int(true_row[2]), int(false_row[2]), float(true_row[5]),
                sum(float(row[6]) for row in metric_rows),
            )
            analysis.add(
                "RQ4", f"rq4_one_gap_{metric}", "allow_one_missing_sec_date",
                int(false_row[2]) + int(true_row[2]),
                "median_difference_persistent_minus_isolated",
                float(true_row[4]) - float(false_row[4]),
                p_value=delta.p_value,
                effect_name="cliffs_delta",
                effect=delta.value,
                method="alternative-gap Mann-Whitney comparison",
            )

        analysis.save()
        analysis.plot_groups()

    run_sql_files([SQL_DIR / "002_results_validation.sql"], args.env_file)
    print(f"saved {len(analysis.results)} results", flush=True)


if __name__ == "__main__":
    main()

