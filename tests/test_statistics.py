from __future__ import annotations

import unittest

import numpy as np

from src.statistics.methods import (
    cliffs_delta,
    cluster_mean_difference,
    correlation_from_sums,
    fisher_correlation_interval,
    kruskal_wallis,
    within_security_estimates,
)


class StatisticalMethodTests(unittest.TestCase):
    def test_correlation_from_sufficient_statistics(self) -> None:
        values = np.array([[1.0, 2.0], [2.0, 4.0], [3.0, 6.0]])
        result = correlation_from_sums(
            3,
            values[:, 0].sum(),
            values[:, 1].sum(),
            np.square(values[:, 0]).sum(),
            np.square(values[:, 1]).sum(),
            np.prod(values, axis=1).sum(),
        )
        self.assertAlmostEqual(result, 1.0)

    def test_fisher_interval_contains_estimate(self) -> None:
        low, high = fisher_correlation_interval(0.2, 100)
        self.assertLess(low, 0.2)
        self.assertGreater(high, 0.2)

    def test_cliffs_delta_has_expected_direction(self) -> None:
        result = cliffs_delta(2, 2, 7.0, 0.0)
        self.assertAlmostEqual(result.value, 1.0)

    def test_kruskal_effect_is_zero_for_equal_rank_means(self) -> None:
        result, epsilon = kruskal_wallis([2, 2], [5.0, 5.0], 0.0)
        self.assertAlmostEqual(result.value, 0.0)
        self.assertEqual(epsilon, 0.0)

    def test_within_security_slope_removes_level_differences(self) -> None:
        moments = np.array(
            [
                [2, 1, 30, 1, 500, 20],
                [2, 1, 210, 1, 22100, 110],
            ],
            dtype=float,
        )
        correlation, slope = within_security_estimates(moments)
        self.assertAlmostEqual(correlation.value, 1.0)
        self.assertAlmostEqual(slope.value, 10.0)

    def test_clustered_mean_difference(self) -> None:
        result = cluster_mean_difference(
            [(1, False, 1, 1.0), (1, True, 1, 2.0), (2, False, 1, 3.0), (2, True, 1, 5.0)]
        )
        self.assertAlmostEqual(result.value, 1.5)


if __name__ == "__main__":
    unittest.main()
