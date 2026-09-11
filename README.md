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

## What I plan to investigate

The analysis will focus on four questions:

1. Do stocks with unusually high short sale activity also have unusually high short interest?
2. Does a change in short sale activity tend to appear before a change in reported short interest?
3. What do short interest and recent short activity look like when a stock has an extreme FTD balance?
4. What separates an FTD spike that lasts one day from a balance that persists across several settlement dates?

The goal is to measure these relationships, not assume they exist. A weak relationship or a null result would still be useful.

## Data

The project will use three free public regulatory datasets:

- FINRA Consolidated NMS Daily Short Sale Volume
- FINRA Equity Short Interest
- SEC Fails-to-Deliver Data

The target period begins in August 2018. Some questions may require a later start if one of the datasets does not have complete coverage for the full period. Missing history will not be treated as zero.

## Approach

PostgreSQL and SQL will handle the core data modeling, joins, rolling calculations, and episode construction. Python will be used for data checks, statistical analysis, and supporting charts. The completed analysis will be presented in Power BI.

This project studies market structure. It is not intended to predict prices, identify short squeezes, or produce trading signals.

## Project status

The data has been downloaded, loaded into PostgreSQL, cleaned, and matched across sources. The short volume, short interest, daily FTD, FTD episode, and formal statistical analyses are complete. Dashboard work has not started.

## Getting the data

The three sources can be acquired with standard Python and no paid API keys:

```powershell
python -m src.ingestion.finra_short_volume
python -m src.ingestion.finra_short_interest
python -m src.ingestion.sec_ftd
```

Each command resumes safely when valid raw files already exist. Raw downloads are stored under `data/raw/` and are excluded from Git. Use `--help` to see date range, worker, and smoke test options.

## Loading PostgreSQL

The repository includes a small Docker Compose setup for PostgreSQL 17. Copy the example environment file, choose a local password, and start the database:

```powershell
Copy-Item .env.example .env
docker compose up -d
```

Create a Python environment and install the PostgreSQL driver:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Load the files already present under `data/raw/`:

```powershell
python -m src.loading.load_all
```

The loader uses PostgreSQL COPY and records a SHA-256 checksum for every file. Running it again skips files that have not changed. If a file changes under the same name, only that file's rows are replaced, inside a transaction.

To check the loaded counts and date coverage against the acquisition results:

```powershell
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/001_counts_and_coverage.sql'
```

## Cleaning and security matching

Build the cleaned tables after loading the raw data:

```powershell
python -m src.cleaning.run
```

The build keeps every raw row and adds quality flags instead of silently deleting questionable records. SEC CUSIPs provide the security anchors. FINRA rows are linked only when their symbol is supported by SEC observations for the relevant date; uncertain rows keep a blank security ID.

Run the database checks and view the quality report with:

```powershell
python -m src.cleaning.run --sql-dir sql/tests
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/003_cleaning_quality.sql'
```

To refresh only the quality, identity, and coverage summaries without rebuilding the large cleaned tables:

```powershell
python -m src.cleaning.run --summaries-only
```

Build the daily short volume ratios and features based on observation windows with:

```powershell
python -m src.features.run
```

The feature table uses only valid rows with identity matches rated high or medium confidence. Rolling values require complete histories of 5, 14, or 30 observations. Recent partial periods are kept for review but left out of the primary analysis window.

After the build, rerun the database assertions and inspect the feature quality reports with:

```powershell
python -m src.cleaning.run --sql-dir sql/tests
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/004_short_volume_features.sql'
```

## Short interest cycle analysis

Build the short interest cycles and align each observation with FINRA activity strictly before its settlement date:

```powershell
python -m src.analysis.run
```

The main analysis uses the preceding 14 observed FINRA trading days. Averages based on 5 and 30 observations are kept for comparison. Changes in short interest use adjacent reporting cycles. Rows after the latest complete shared month remain stored but are excluded from the main cohort results.

Run the assertions and descriptive report with:

```powershell
python -m src.cleaning.run --sql-dir sql/tests
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/005_short_interest_quality.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/006_short_interest_results.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/007_short_interest_sensitivity.sql'
```

The report contains descriptive correlations and summaries based on fixed groups. Settlement dates show when the values were measured. Historical publication dates are unavailable, so these results do not show what investors knew at the time.

## FTD observation analysis

The analysis runner also builds one row for each SEC FTD record that passes the data checks. FTD quantity is treated as an outstanding balance, not as new failures created that day. Approximate value uses the SEC reference price when available and remains null when the price is missing.

The first 200 observations for each security form a fixed historical baseline. Later observations are compared with thresholds at the 95th, 99th, and 99.5th percentiles. Short volume comes strictly before the FTD settlement date. Short interest comes from the latest settlement observation on or before that date.

Run the FTD reports with:

```powershell
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/008_ftd_quality.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/009_ftd_results.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/010_ftd_sensitivity.sql'
```

## FTD episode analysis

The analysis runner also groups daily FTD observations into episodes. An episode continues when the same security appears on the next observed SEC settlement date and the calendar gap is no longer than four days. This keeps weekends and ordinary market holidays together while breaking episodes at longer gaps in the source data.

An isolated episode has one observation. A persistent episode has two or more. The table records episode length, peak quantity, recurrence, prior short volume, and the latest short interest observation on or before the episode start. It also stores `ftd_balance_days`, the sum of the daily outstanding balances in an episode. This is an intensity measure, not a count of newly failed shares.

Run the episode reports with:

```powershell
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/011_ftd_episode_quality.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/012_ftd_episode_results.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/013_ftd_episode_sensitivity.sql'
```

The primary results end in July 2026. Later observations remain in the table but are marked as outside the complete shared period. Episodes touching the beginning or end of the available FTD history are also marked as censored.

For short interest reported on exchanges, 97.68% of rows received a supported match. Daily short volume matched at 97.59%. These figures include exact matches on the same date and lower confidence matches within a symbol date range supported by SEC data. The report shows the two groups separately. The 100% reported for SEC FTD rows only means that each valid CUSIP identifies its own row. It is not a match rate across datasets.

## Statistical analysis

Run the formal analysis after building the earlier analysis tables:

```powershell
python -m src.statistics.run
```

The runner calculates pooled and within-security effects, clustered confidence intervals, predetermined cohort comparisons, and the planned sensitivity checks. Results are stored in `market_structure.statistical_results`. P-values are included, but the analysis treats effect size and stability as the main evidence because the samples contain millions of observations.
