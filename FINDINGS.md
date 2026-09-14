# Findings

The main analysis runs from August 2018 through July 31, 2026. It uses high and medium confidence security matches. I also reran the important comparisons with stricter identity rules, different time windows, broad time periods, and alternative FTD episode rules.

Because some samples contain millions of rows, p values are not very helpful on their own. A tiny relationship can be measured very precisely and still have little practical meaning. The results below focus on the size of each relationship and whether it survives the checks.

## RQ1: Does high short activity come with high short interest?

Yes, but the relationship is weak.

| Result | Value |
|---|---:|
| Observations | 1,923,712 |
| Pearson correlation | 0.156 |
| Spearman correlation | 0.171 |
| Spearman 95% clustered interval | 0.167 to 0.174 |
| Spearman correlation within each security | 0.236 |
| Top versus bottom activity decile, Cliff's delta | 0.296 |

The positive result does not disappear when each security is compared with itself. It is not equally strong everywhere, though. Among securities with enough observations, the median individual correlation is 0.204 and the middle half runs from -0.021 to 0.396.

Changing the short volume window does little to the main result. The correlations for 5, 14, and 30 observations are 0.167, 0.171, and 0.163. The estimates also remain positive across the three broad time periods, ranging from 0.112 to 0.236.

The biggest warning comes from the strict identity check. Requiring high confidence everywhere cuts the sample from 1.92 million rows to 46,285 and lowers the correlation to 0.051. That smaller sample is not directly comparable to the main population, but it does mean the RQ1 result should be described carefully.

My reading is that recent short activity contains some information about outstanding short interest, but far less than the similar names might suggest.

## RQ2: Do activity changes line up with later short interest changes?

This is the strongest result connecting short volume and short interest in the project, although it is still modest.

| Result | Value |
|---|---:|
| Observations | 1,886,458 |
| Pearson correlation | 0.146 |
| Spearman correlation | 0.186 |
| Spearman 95% clustered interval | 0.184 to 0.187 |
| Spearman correlation within each security | 0.212 |
| Extreme increase versus decrease, Cliff's delta | 0.347 |

The extreme activity decrease group has a median signed log change in short interest of -0.083. The extreme increase group has a median of 0.089, making the gap 0.171.

The result stays positive after dropping the lowest volume decile, using only high confidence identities, and splitting the sample into broad periods. The correlation for the high confidence sample is 0.154, and the period estimates range from 0.164 to 0.202.

Ordinary percentage change performs poorly when the earlier short interest value is close to zero. Signed log change avoids that denominator problem and is the main outcome.

The short volume window comes before the short interest settlement date. That ordering is useful, but it does not show that one caused the other or that the relationship could have been traded in real time.

## RQ3: What surrounds an extreme FTD balance?

FTDs that are large relative to a security's own history tend to occur with somewhat higher short interest and prior short activity. Neither relationship is strong.

| Relationship | Observations | Spearman correlation |
|---|---:|---:|
| Relative FTD intensity and short interest percentile | 5,029,823 | 0.161 |
| Relative FTD intensity and prior short activity percentile | 5,028,900 | 0.119 |

Short interest percentile rises from a median of 0.555 below the historical p95 FTD threshold to 0.763 at p99.5 or above.

| FTD threshold | Short interest Cliff's delta | Prior activity Cliff's delta |
|---|---:|---:|
| p95 | 0.255 | 0.149 |
| p99 | 0.296 | 0.154 |
| p99.5 | 0.305 | 0.158 |

The short interest difference becomes moderately larger at stricter FTD thresholds. The prior activity difference stays small. Requiring the aligned short interest observation to be no more than 30 days old barely changes the main correlation, and all three broad time periods keep the same direction.

Raw FTD quantity works less well because securities differ so much in size. Comparing each FTD with that security's own past produces a more useful measure.

The dashboard's p99 breakdown also matters: most extreme FTD observations do not have high short interest and high short activity at the same time.

## RQ4: What separates persistent FTD episodes from isolated ones?

Persistent episodes mainly stand out because their FTD balances are more severe.

| Comparison | Median difference | Cliff's delta |
|---|---:|---:|
| Peak historical FTD intensity | 0.250 | 0.438 |
| Peak FTD quantity | 2,545 shares | 0.424 |
| Prior short activity percentile | 0.046 | 0.076 |
| Short interest percentile | 0.013 | 0.020 |

The first two effects are moderate. Prior short activity differs only slightly, while short interest is almost the same for persistent and isolated episodes.

Balance days has a larger effect of 0.532, but part of that is automatic: an episode that lasts longer has more observation dates to add together. Peak quantity and peak historical intensity are cleaner comparisons.

Allowing one missing SEC observation date lowers the short interest effect to 0.013 and the prior activity effect to 0.063. The basic conclusion does not change. The strict identity sample is less stable because it contains only about 23,000 to 24,000 episodes. In that sample, the short interest effect changes to -0.038 and the prior activity effect rises to 0.247. I treat that as a warning about sample composition rather than a replacement for the main result.

## Bottom line

The three statistics share some information, but they are not different versions of the same measure. Changes in short activity line up with short interest changes better than their levels line up, but even that relationship is modest. Extreme and persistent FTDs are much easier to distinguish by looking at the FTD balance itself than by looking for unusually high short activity or short interest beforehand.

Nothing here establishes causation, manipulation, naked short selling, price predictability, or a trading signal.
