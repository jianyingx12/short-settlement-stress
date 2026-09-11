from __future__ import annotations

from dataclasses import dataclass
from math import atanh, exp, isfinite, sqrt, tanh
from typing import Iterable

import numpy as np
from scipy import stats


@dataclass(frozen=True)
class Estimate:
    value: float
    confidence_low: float | None
    confidence_high: float | None
    p_value: float | None


def correlation_from_sums(
    n: float,
    sum_x: float,
    sum_y: float,
    sum_xx: float,
    sum_yy: float,
    sum_xy: float,
) -> float:
    centered_xx = sum_xx - sum_x * sum_x / n
    centered_yy = sum_yy - sum_y * sum_y / n
    centered_xy = sum_xy - sum_x * sum_y / n
    if centered_xx <= 0 or centered_yy <= 0:
        return float("nan")
    return centered_xy / sqrt(centered_xx * centered_yy)


def fisher_correlation_interval(correlation: float, n: int) -> tuple[float, float]:
    if n <= 3 or not isfinite(correlation) or abs(correlation) >= 1:
        return float("nan"), float("nan")
    distance = stats.norm.ppf(0.975) / sqrt(n - 3)
    transformed = atanh(correlation)
    return tanh(transformed - distance), tanh(transformed + distance)


def correlation_p_value(correlation: float, n: int) -> float:
    if n <= 2 or not isfinite(correlation):
        return float("nan")
    if abs(correlation) >= 1:
        return 0.0
    statistic = correlation * sqrt((n - 2) / (1 - correlation * correlation))
    return float(2 * stats.t.sf(abs(statistic), df=n - 2))


def cluster_bootstrap_correlation(
    moments: np.ndarray,
    *,
    repetitions: int = 400,
    seed: int = 20260910,
    within: bool = False,
) -> tuple[float, float]:
    """Bootstrap a correlation by resampling whole security histories."""
    if moments.ndim != 2 or moments.shape[1] != 6:
        raise ValueError("moments must contain n, sx, sy, sxx, syy, and sxy")
    if len(moments) < 2:
        return float("nan"), float("nan")

    values = moments.astype(float, copy=True)
    if within:
        n, sx, sy, sxx, syy, sxy = values.T
        values = np.column_stack(
            (
                n,
                np.zeros_like(n),
                np.zeros_like(n),
                sxx - sx * sx / n,
                syy - sy * sy / n,
                sxy - sx * sy / n,
            )
        )

    random = np.random.default_rng(seed)
    estimates = np.empty(repetitions)
    cluster_count = len(values)
    for index in range(repetitions):
        selected = random.integers(0, cluster_count, size=cluster_count)
        totals = values[selected].sum(axis=0)
        estimates[index] = correlation_from_sums(*totals)
    return tuple(np.nanquantile(estimates, [0.025, 0.975]))


def within_security_estimates(moments: np.ndarray) -> tuple[Estimate, Estimate]:
    """Return the within-security correlation and fixed-effects slope."""
    n, sum_x, sum_y, sum_xx, sum_yy, sum_xy = moments.astype(float).T
    centered_xx = sum_xx - sum_x * sum_x / n
    centered_yy = sum_yy - sum_y * sum_y / n
    centered_xy = sum_xy - sum_x * sum_y / n

    total_xx = centered_xx.sum()
    total_yy = centered_yy.sum()
    total_xy = centered_xy.sum()
    correlation = total_xy / sqrt(total_xx * total_yy)
    correlation_low, correlation_high = cluster_bootstrap_correlation(
        moments, within=True
    )

    slope = total_xy / total_xx
    cluster_scores = centered_xy - slope * centered_xx
    cluster_count = len(moments)
    standard_error = sqrt(
        cluster_count / (cluster_count - 1)
        * np.square(cluster_scores).sum()
        / (total_xx * total_xx)
    )
    slope_low = slope - stats.norm.ppf(0.975) * standard_error
    slope_high = slope + stats.norm.ppf(0.975) * standard_error
    p_value = 0.0 if standard_error == 0 and slope != 0 else float(
        2 * stats.norm.sf(abs(slope / standard_error))
    )

    return (
        Estimate(correlation, correlation_low, correlation_high, None),
        Estimate(slope, slope_low, slope_high, p_value),
    )


def security_correlation_summary(moments: np.ndarray) -> dict[str, float]:
    n, sum_x, sum_y, sum_xx, sum_yy, sum_xy = moments.astype(float).T
    centered_xx = sum_xx - sum_x * sum_x / n
    centered_yy = sum_yy - sum_y * sum_y / n
    centered_xy = sum_xy - sum_x * sum_y / n
    usable = (n >= 12) & (centered_xx > 0) & (centered_yy > 0)
    correlations = centered_xy[usable] / np.sqrt(centered_xx[usable] * centered_yy[usable])
    return {
        "securities": float(len(correlations)),
        "median": float(np.median(correlations)),
        "q25": float(np.quantile(correlations, 0.25)),
        "q75": float(np.quantile(correlations, 0.75)),
        "positive_share": float(np.mean(correlations > 0)),
    }


def cliffs_delta(
    true_count: int,
    false_count: int,
    true_rank_sum: float,
    tie_term: float,
) -> Estimate:
    """Compare the true group with the false group using average ranks."""
    total = true_count + false_count
    u_statistic = true_rank_sum - true_count * (true_count + 1) / 2
    delta = 2 * u_statistic / (true_count * false_count) - 1
    variance = true_count * false_count / 12 * (
        total + 1 - tie_term / (total * (total - 1))
    )
    z_score = (u_statistic - true_count * false_count / 2) / sqrt(variance)
    p_value = float(2 * stats.norm.sf(abs(z_score)))
    return Estimate(float(delta), None, None, p_value)


def kruskal_wallis(
    group_counts: Iterable[int],
    group_rank_sums: Iterable[float],
    tie_term: float,
) -> tuple[Estimate, float]:
    counts = np.asarray(tuple(group_counts), dtype=float)
    rank_sums = np.asarray(tuple(group_rank_sums), dtype=float)
    total = counts.sum()
    statistic = 12 / (total * (total + 1)) * np.sum(rank_sums**2 / counts) - 3 * (
        total + 1
    )
    tie_correction = 1 - tie_term / (total**3 - total)
    statistic /= tie_correction
    degrees_of_freedom = len(counts) - 1
    p_value = float(stats.chi2.sf(statistic, degrees_of_freedom))
    epsilon_squared = max(0.0, (statistic - degrees_of_freedom) / (total - len(counts)))
    return Estimate(float(statistic), None, None, p_value), float(epsilon_squared)


def cluster_mean_difference(rows: Iterable[tuple[int, bool, int, float]]) -> Estimate:
    """Difference in means with a security-cluster robust interval."""
    grouped: dict[int, list[float]] = {}
    for security_id, is_true, count, value_sum in rows:
        values = grouped.setdefault(security_id, [0.0, 0.0, 0.0, 0.0])
        offset = 2 if is_true else 0
        values[offset] += count
        values[offset + 1] += value_sum

    array = np.asarray(tuple(grouped.values()), dtype=float)
    false_n, false_sum, true_n, true_sum = array.T
    false_mean = false_sum.sum() / false_n.sum()
    true_mean = true_sum.sum() / true_n.sum()
    difference = true_mean - false_mean
    influence = (
        (true_sum - true_mean * true_n) / true_n.sum()
        - (false_sum - false_mean * false_n) / false_n.sum()
    )
    cluster_count = len(array)
    standard_error = sqrt(cluster_count / (cluster_count - 1) * np.square(influence).sum())
    critical = stats.norm.ppf(0.975)
    p_value = float(2 * stats.norm.sf(abs(difference / standard_error)))
    return Estimate(
        float(difference),
        float(difference - critical * standard_error),
        float(difference + critical * standard_error),
        p_value,
    )
