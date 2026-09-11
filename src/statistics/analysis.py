from __future__ import annotations

import csv
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
from matplotlib import pyplot as plt

from src.statistics.methods import (
    Estimate,
    cliffs_delta,
    cluster_bootstrap_correlation,
    cluster_mean_difference,
    correlation_from_sums,
    correlation_p_value,
    fisher_correlation_interval,
    kruskal_wallis,
    security_correlation_summary,
    within_security_estimates,
)
from src.statistics.queries import (
    clustered_binary_sums,
    cluster_moments,
    period_correlations,
    ranked_group_summary,
    simple_correlations,
    within_rank_moments,
)


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = PROJECT_ROOT / "docs" / "statistics"


@dataclass(frozen=True)
class Result:
    research_question: str
    analysis_name: str
    sample: str
    observation_count: int
    estimate_name: str
    estimate: float | None
    confidence_low: float | None
    confidence_high: float | None
    p_value: float | None
    effect_size_name: str | None
    effect_size: float | None
    method: str
    notes: str | None = None


def finite(value: object) -> float | None:
    if value is None:
        return None
    converted = float(value)
    return converted if np.isfinite(converted) else None


class Analysis:
    def __init__(self, connection: object) -> None:
        self.connection = connection
        self.results: list[Result] = []
        self.group_summaries: dict[str, list[tuple[str, int, float, float]]] = {}

    def query(self, statement: str) -> list[tuple[object, ...]]:
        started = time.perf_counter()
        with self.connection.cursor() as cursor:
            cursor.execute(statement)
            rows = cursor.fetchall()
        print(f"query: {time.perf_counter() - started:.1f}s", flush=True)
        return rows

    def add(
        self,
        rq: str,
        analysis_name: str,
        sample: str,
        n: int,
        estimate_name: str,
        estimate: float | None,
        *,
        interval: tuple[float | None, float | None] = (None, None),
        p_value: float | None = None,
        effect_name: str | None = None,
        effect: float | None = None,
        method: str,
        notes: str | None = None,
    ) -> None:
        self.results.append(
            Result(
                rq,
                analysis_name,
                sample,
                n,
                estimate_name,
                finite(estimate),
                finite(interval[0]),
                finite(interval[1]),
                finite(p_value),
                effect_name,
                finite(effect),
                method,
                notes,
            )
        )

    def analyze_pair(
        self,
        rq: str,
        name: str,
        table: str,
        x: str,
        y: str,
        where: str,
        *,
        within: bool = False,
    ) -> None:
        print(f"{rq} {name}", flush=True)
        rows = self.query(cluster_moments(table, x, y, where))
        values = np.asarray([[float(value) for value in row[1:]] for row in rows])
        raw = values[:, :6]
        ranked = np.column_stack((values[:, 0], values[:, 6:11]))
        n = int(raw[:, 0].sum())

        for estimate_name, moments in (("pearson", raw), ("spearman", ranked)):
            totals = moments.sum(axis=0)
            correlation = correlation_from_sums(*totals)
            interval = cluster_bootstrap_correlation(moments)
            self.add(
                rq,
                name,
                "primary_high_and_medium",
                n,
                estimate_name,
                correlation,
                interval=interval,
                p_value=correlation_p_value(correlation, n),
                effect_name="correlation",
                effect=correlation,
                method="pooled correlation with security-cluster bootstrap CI",
                notes="The p-value treats rows as independent; use the clustered interval and effect size for interpretation.",
            )

        if not within:
            return

        within_correlation, slope = within_security_estimates(raw)
        self.add_estimate(
            rq,
            f"{name}_within_security",
            "primary_high_and_medium",
            n,
            "within_pearson",
            within_correlation,
            "security-demeaned correlation with cluster bootstrap CI",
            "Removes stable differences in average levels between securities.",
        )
        self.add_estimate(
            rq,
            f"{name}_within_security",
            "primary_high_and_medium",
            n,
            "fixed_effects_slope",
            slope,
            "security fixed-effects regression with clustered standard error",
            "Association estimate only; no causal or forecasting interpretation.",
        )

        rank_rows = self.query(within_rank_moments(table, x, y, where))
        within_ranks = np.asarray(
            [[float(value) for value in row[1:]] for row in rank_rows]
        )
        rank_correlation, _ = within_security_estimates(within_ranks)
        self.add_estimate(
            rq,
            f"{name}_within_security",
            "primary_high_and_medium",
            int(within_ranks[:, 0].sum()),
            "within_spearman",
            rank_correlation,
            "within-security ranks with cluster bootstrap CI",
            "Ranks are calculated separately inside each security history.",
        )

        summary = security_correlation_summary(raw)
        for metric in ("median", "q25", "q75", "positive_share"):
            self.add(
                rq,
                f"{name}_security_distribution",
                "securities_with_at_least_12_observations",
                int(summary["securities"]),
                metric,
                summary[metric],
                method="distribution of security-level Pearson correlations",
            )

    def add_estimate(
        self,
        rq: str,
        analysis_name: str,
        sample: str,
        n: int,
        estimate_name: str,
        estimate: Estimate,
        method: str,
        notes: str | None = None,
    ) -> None:
        self.add(
            rq,
            analysis_name,
            sample,
            n,
            estimate_name,
            estimate.value,
            interval=(estimate.confidence_low, estimate.confidence_high),
            p_value=estimate.p_value,
            effect_name=estimate_name,
            effect=estimate.value,
            method=method,
            notes=notes,
        )

    def analyze_groups(
        self,
        rq: str,
        name: str,
        table: str,
        group: str,
        value: str,
        where: str,
    ) -> None:
        print(f"{rq} {name}", flush=True)
        rows = self.query(ranked_group_summary(table, group, value, where))
        summaries = [
            (str(row[0]), int(row[1]), float(row[2]), float(row[3])) for row in rows
        ]
        self.group_summaries[name] = summaries
        total = sum(row[1] for row in summaries)
        test, epsilon = kruskal_wallis(
            [int(row[1]) for row in rows],
            [float(row[5]) for row in rows],
            sum(float(row[6]) for row in rows),
        )
        self.add(
            rq,
            name,
            "primary_high_and_medium",
            total,
            "kruskal_wallis_h",
            test.value,
            p_value=test.p_value,
            effect_name="epsilon_squared",
            effect=epsilon,
            method="Kruskal-Wallis with tie correction",
            notes="Epsilon-squared, not the p-value, measures the practical group separation.",
        )
        for label, count, mean, median in summaries:
            self.add(
                rq,
                name,
                label,
                count,
                "median",
                median,
                method="exact group median",
            )
            self.add(
                rq,
                name,
                label,
                count,
                "mean",
                mean,
                method="group mean",
            )

    def analyze_binary(
        self,
        rq: str,
        name: str,
        table: str,
        group: str,
        value: str,
        where: str,
        sample: str = "primary_high_and_medium",
    ) -> None:
        print(f"{rq} {name}", flush=True)
        rows = self.query(ranked_group_summary(table, group, value, where))
        by_group = {str(row[0]).lower(): row for row in rows}
        false_row = by_group["false"]
        true_row = by_group["true"]
        false_n, true_n = int(false_row[1]), int(true_row[1])
        tie_term = sum(float(row[6]) for row in rows)
        delta = cliffs_delta(true_n, false_n, float(true_row[5]), tie_term)
        median_difference = float(true_row[3]) - float(false_row[3])
        self.group_summaries[name] = [
            (str(row[0]).lower(), int(row[1]), float(row[2]), float(row[3]))
            for row in rows
        ]

        clustered_rows = self.query(clustered_binary_sums(table, group, value, where))
        mean_difference = cluster_mean_difference(
            (int(row[0]), bool(row[1]), int(row[2]), float(row[3]))
            for row in clustered_rows
        )
        total = true_n + false_n
        self.add(
            rq,
            name,
            sample,
            total,
            "median_difference_true_minus_false",
            median_difference,
            p_value=delta.p_value,
            effect_name="cliffs_delta",
            effect=delta.value,
            method="Mann-Whitney comparison with Cliff's delta",
            notes="The p-value is secondary; Cliff's delta describes stochastic separation.",
        )
        self.add_estimate(
            rq,
            name,
            sample,
            total,
            "mean_difference_true_minus_false",
            mean_difference,
            "mean difference with security-cluster robust CI",
        )

    def simple_pair(
        self,
        rq: str,
        name: str,
        table: str,
        x: str,
        y: str,
        where: str,
        sample: str,
    ) -> None:
        row = self.query(simple_correlations(table, x, y, where, sample))[0]
        n = int(row[1])
        for estimate_name, value in (("pearson", row[2]), ("spearman", row[3])):
            correlation = float(value)
            self.add(
                rq,
                name,
                sample,
                n,
                estimate_name,
                correlation,
                effect_name="correlation",
                effect=correlation,
                method="correlation sensitivity",
                notes="Compare this effect estimate with the primary result.",
            )

    def analyze_periods(
        self,
        rq: str,
        name: str,
        table: str,
        date: str,
        x: str,
        y: str,
        where: str,
    ) -> None:
        for period, count, pearson, spearman in self.query(
            period_correlations(table, date, x, y, where)
        ):
            n = int(count)
            for estimate_name, value in (("pearson", pearson), ("spearman", spearman)):
                correlation = float(value)
                self.add(
                    rq,
                    name,
                    str(period),
                    n,
                    estimate_name,
                    correlation,
                    effect_name="correlation",
                    effect=correlation,
                    method="period-stratified correlation",
                    notes="Compare effect size and direction across periods.",
                )

    def save(self) -> None:
        statement = """
            INSERT INTO market_structure.statistical_results (
                research_question, analysis_name, sample, observation_count,
                estimate_name, estimate, confidence_low, confidence_high,
                p_value, effect_size_name, effect_size, method, notes
            ) VALUES (
                %(research_question)s, %(analysis_name)s, %(sample)s,
                %(observation_count)s, %(estimate_name)s, %(estimate)s,
                %(confidence_low)s, %(confidence_high)s, %(p_value)s,
                %(effect_size_name)s, %(effect_size)s, %(method)s, %(notes)s
            )
        """
        with self.connection.cursor() as cursor:
            cursor.executemany(statement, [asdict(result) for result in self.results])

        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        with (OUTPUT_DIR / "statistical_results.csv").open(
            "w", newline="", encoding="utf-8"
        ) as output:
            writer = csv.DictWriter(output, fieldnames=asdict(self.results[0]).keys())
            writer.writeheader()
            writer.writerows(asdict(result) for result in self.results)

    def plot_groups(self) -> None:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        settings = {
            "rq1_activity_cohorts": (
                "Short interest by prior short activity",
                ["bottom_10", "10_to_25", "25_to_50", "50_to_75", "75_to_90", "top_10"],
            ),
            "rq2_activity_change_cohorts": (
                "Short interest change by activity change",
                ["extreme_decrease", "moderate_decrease", "typical", "moderate_increase", "extreme_increase"],
            ),
            "rq3_ftd_severity_cohorts": (
                "Short interest by relative FTD severity",
                ["below_p95", "p95_to_p99", "p99_to_p995", "p995_plus"],
            ),
            "rq4_persistent_prior_short_activity": (
                "Prior short activity by episode class",
                ["false", "true"],
            ),
        }
        for name, (title, order) in settings.items():
            rows_by_label = {row[0]: row for row in self.group_summaries[name]}
            rows = [rows_by_label[label] for label in order]
            labels = [row[0].replace("_", " ") for row in rows]
            medians = [row[3] for row in rows]
            figure, axis = plt.subplots(figsize=(8, 4.5))
            axis.plot(labels, medians, marker="o")
            axis.set_title(title)
            axis.set_ylabel("Median")
            axis.tick_params(axis="x", rotation=30)
            figure.tight_layout()
            figure.savefig(OUTPUT_DIR / f"{name}.png", dpi=150)
            plt.close(figure)


