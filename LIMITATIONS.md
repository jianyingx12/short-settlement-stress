# Limitations

This project combines three large regulatory datasets, but having a lot of rows does not remove the limits of what those records can tell us. These are the issues that matter most when reading the results.

## The measures describe different things

FINRA daily short sale volume is reported trading activity. It is not a record of positions that stayed open, and the consolidated files do not cover every short sale in the United States.

Short interest is an outstanding position measured at a FINRA settlement snapshot, normally twice a month. It cannot show daily openings and closings between those dates.

SEC FTD quantity is also an outstanding balance. It is not the number of new failures created that day. A fail can come from a long or short transaction, so the data cannot prove naked short selling or manipulation.

## The common period ends in July 2026

There are source rows after July 2026, but August is not complete across all three datasets. The main results stop on July 31 instead of treating partial coverage as a complete month.

A date without an FTD row does not automatically mean that a new value of zero was reported. Missing source history is also left missing rather than filled in.

The short interest files contain settlement dates but not their historical publication timestamps. This project can compare measures by settlement date, but it cannot reconstruct exactly what investors knew on that date.

## Matching historical securities requires judgment

SEC CUSIPs provide the identity anchor. FINRA symbols are matched only when the SEC history supports the symbol and CUSIP around the date of the FINRA row. Current ticker lists and fuzzy company names are not used to fill gaps because they can create convincing but false historical joins.

The supported match rates are 97.68% for exchange listed short interest and 97.59% for daily short volume. Ambiguous and unresolved rows do not receive a security ID. The ID represents a security identified by its CUSIP, not a permanent company, so a CUSIP change normally starts a new identity.

The main analysis allows high and medium confidence matches. Checks that use only high confidence matches can be much smaller and can contain a different mix of securities. RQ1 is the clearest example: its Spearman correlation drops from 0.171 in 1.92 million observations to 0.051 in 46,285 observations. Some RQ4 effects also move noticeably in the strict sample.

## The timing is careful but incomplete

Short volume windows end before the short interest or FTD settlement date used in a comparison. FTD rows receive the latest short interest settlement observation on or before their date. This prevents future rows from leaking into the calculation.

It does not reveal how long an individual position stayed open, when it was closed, why a trade was marked short, or when a historical short interest value became public. A prior date is not the same as a proven causal sequence.

The main short volume feature covers 14 observed trading days. Results are similar with 5 and 30 observations, but every rolling average hides some of the daily variation inside its window.

## FTD thresholds and episodes are definitions

An extreme FTD is measured against the security's own earlier history. This is more useful than comparing raw quantities across companies of very different sizes, but it also means the measure is relative. A security needs enough earlier records before the historical percentile can be calculated.

An episode continues when the same security appears on the next observed SEC settlement date and the calendar gap is four days or less. A separate check allows one missing SEC observation date. The main conclusion survives, but the exact episode counts and effects change.

Balance days should be read cautiously because it grows automatically when an episode lasts longer. Peak quantity and peak historical intensity are better evidence that persistent episodes are more severe.

## Statistical significance can be misleading here

The same securities appear repeatedly over time. The analysis resamples whole security histories, uses clustered standard errors, compares observations within each security, and checks broad time periods. It does not model every date shock across the whole market or every possible dependency over time.

Millions of observations can give a tiny effect an extremely small p value. Persistent and isolated episodes, for example, differ by only 0.013 in median short interest percentile and have a negligible Cliff's delta of 0.020. The p value is still extremely small. That is why the project gives more weight to effect size, uncertainty, sample composition, and sensitivity checks.

The short interest percentile used in the descriptive comparisons is calculated from each security's full observed history. It is useful for comparing records within a security, but it is a retrospective measure rather than something that would have been available in real time.

## What should not be concluded

This is an observational study. It cannot show that short selling caused a failure to deliver, that an FTD caused a later position change, or that any of these measures predicts prices.

The results are not evidence of manipulation, naked short selling, a coming short squeeze, or a trading opportunity.
