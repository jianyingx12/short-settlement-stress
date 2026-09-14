# Short Selling & Settlement Stress

Short selling produces several widely reported market statistics. Three of the most common are **short interest**, **daily short sale volume**, and **failures to deliver**. They sound similar, but they measure different parts of the trading and settlement process.

This project asks a simple question: **How closely are these measures actually related, and when do they tell different stories about the same stock?**

## What do these measures mean?

### Short interest

Short interest is the number of shares that have been sold short and remain open at a specific point in time.

Think of it as a snapshot. If a stock has short interest of 1 million shares, reporting firms had 1 million shares recorded as open short positions on that settlement date. FINRA publishes this information about twice a month, so it does not show what happens day by day.

### Daily short sale volume

Daily short sale volume is the number of shares executed as short sales during a trading day.

Think of it as activity rather than an open balance. A stock could have heavy short sale volume even if many of those positions are closed quickly and never appear in the next short interest snapshot. The FINRA data used here covers publicly reported trades handled through certain FINRA facilities. It does not represent every short sale in the U.S. market.

### Failures to deliver

A failure to deliver, or FTD, occurs when shares are not delivered by the required settlement date.

The SEC data reports the total outstanding fail balance for a security on each settlement date. It is not a count of new failures created that day. FTDs can result from long or short transactions, so an FTD is not proof of naked short selling.

### Why the difference matters

These measures answer different questions:

| Measure | What it tells us |
|---|---|
| Short interest | How many short positions remain open at a reporting snapshot? |
| Daily short sale volume | How much short sale activity was reported through FINRA facilities that day? |
| Failures to deliver | How many shares remained undelivered on a settlement date? |

A stock can therefore have high daily short sale volume but modest short interest, or a large FTD balance without unusually high short activity. Treating the measures as interchangeable can lead to misleading conclusions.

## What I planned to investigate

The analysis focused on four questions:

1. Do stocks with unusually high short sale activity also have unusually high short interest?
2. Does a change in short sale activity tend to appear before a change in reported short interest?
3. What do short interest and recent short activity look like when a stock has an extreme FTD balance?
4. What separates an FTD spike that lasts one day from a balance that persists across several settlement dates?

The goal was to measure these relationships, not assume they exist. A weak relationship or a null result would still be useful.

## Data used

The project uses three free public regulatory datasets:

* [FINRA Consolidated NMS Daily Short Sale Volume](https://www.finra.org/finra-data/browse-catalog/short-sale-volume-data/daily-short-sale-volume-files)
* [FINRA Equity Short Interest](https://www.finra.org/finra-data/browse-catalog/equity-short-interest)
* [SEC Fails to Deliver Data](https://www.sec.gov/data-research/sec-markets-data/fails-deliver-data)

The target period begins in August 2018, and the final results end on July 31, 2026. Missing history is not treated as zero.

## Approach

PostgreSQL and SQL handle the core data modeling, joins, rolling calculations, and episode construction. Python is used for data checks and statistical analysis. The completed analysis is presented in Power BI.

This project studies market structure. It is not intended to predict prices, identify short squeezes, or produce trading signals.

## What I found

The analysis was built around four questions.

1. **Does high short activity come with high short interest?** Usually, but only weakly. The main Spearman correlation is 0.171. The result remains positive within the same security, although it becomes much weaker in the strictest identity sample.

2. **Do changes in short activity line up with later changes in short interest?** This is the clearest relationship in the project, but it is still modest. The Spearman correlation is 0.186, and the extreme increase and decrease groups have a Cliff's delta of 0.347.

3. **What is happening when an FTD balance is extreme for that security?** Short interest has a Spearman correlation of 0.161 with relative FTD intensity. Prior short activity has a smaller correlation of 0.119. Most p99 FTD observations do not have both high short interest and high short activity at the same time.

4. **What separates persistent FTD episodes from isolated ones?** Mainly the severity of the FTD balance. Cliff's delta is 0.438 for peak historical intensity and 0.424 for peak quantity. The effects for prior short activity and short interest are only 0.076 and 0.020.

The samples are large enough to make tiny effects look statistically significant. I therefore focused on effect sizes, clustered confidence intervals, results within each security, and sensitivity checks instead of treating p values as the conclusion.

The full results are in [FINDINGS.md](FINDINGS.md). The important qualifications are in [LIMITATIONS.md](LIMITATIONS.md).

## How the project works

PostgreSQL does most of the heavy lifting because the source and cleaned tables contain tens of millions of rows. Python handles acquisition, loading, statistical calculations, and database orchestration. Power BI reads a small reporting layer instead of importing the full analytical tables.

| Stage | What it does | Entry point |
|---|---|---|
| Acquisition | Downloads and validates the FINRA and SEC files | `src/ingestion` |
| Loading | Copies raw rows into PostgreSQL and records file hashes | `src/loading/load_all.py` |
| Cleaning | Keeps the source rows, adds quality flags, and matches securities | `src/cleaning/run.py` |
| Features | Builds short volume ratios and rolling windows | `src/features/run.py` |
| Analysis | Aligns settlement dates and builds FTD episodes | `src/analysis/run.py` |
| Statistics | Calculates the final estimates and sensitivity checks | `src/statistics/run.py` |
| Reporting | Creates the smaller Power BI tables and views | `src/reporting/run.py` |

Security matching is intentionally conservative. SEC CUSIPs anchor the identity table. A FINRA row receives a security ID only when the historical SEC records support that symbol and CUSIP around the relevant date. Ambiguous rows stay unmatched instead of being forced into a join.

The supported match rate is 97.68% for the exchange listed short interest population and 97.59% for daily short volume. The main analysis includes high and medium confidence matches. I also ran a stricter check using only high confidence matches.

Short volume windows always end before the settlement date being studied. The window of 14 observations is the main specification, while windows of 5 and 30 observations are used as checks. For an FTD row, short interest comes from the latest settlement observation on or before the FTD date.

FTD size is judged against each security's own earlier history. This avoids comparing the raw share balance of a small security directly with that of a much larger one. Consecutive FTD observations are also grouped into episodes so isolated records can be compared with balances that persist.

## Power BI dashboard

The finished [Power BI report](dashboard/short-selling-settlement-stress.pbix) has four pages:

* **Market Overview** explains the measures and shows their distributions and main correlations.
* **Security Explorer** follows short interest, short volume, and FTDs for one selected security.
* **FTD Episodes** compares isolated and persistent episodes.
* **Relationship Analysis** shows the main cohorts, extreme FTD regimes, and effect sizes.

The summary tables use Import mode. The three Security Explorer timelines use DirectQuery, so the detailed history stays in PostgreSQL instead of being packed into the PBIX.

## What this project cannot show

This analysis cannot tell us why a trade was marked short, why a delivery failed, or what information investors knew on a settlement date. It also cannot turn these relationships into evidence of manipulation, naked short selling, price predictability, or a short squeeze.

See [LIMITATIONS.md](LIMITATIONS.md) for the full discussion.
