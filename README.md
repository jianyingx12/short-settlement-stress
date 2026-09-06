# Short Selling & Settlement Stress

Short selling produces several widely reported market statistics. Three of the most common are **short interest**, **daily short-sale volume**, and **failures to deliver**. They sound similar, but they measure different parts of the trading and settlement process.

This project asks a simple question: **How closely are these measures actually related, and when do they tell different stories about the same stock?**

## What do these measures mean?

### Short interest

Short interest is the number of shares that have been sold short and remain open at a specific point in time.

Think of it as a snapshot. If a stock has short interest of 1 million shares, reporting firms had 1 million shares recorded as open short positions on that settlement date. FINRA publishes this information about twice a month, so it does not show what happens day by day.

### Daily short-sale volume

Daily short-sale volume is the number of shares executed as short sales during a trading day.

Think of it as activity rather than an open balance. A stock could have heavy short-sale volume even if many of those positions are closed quickly and never appear in the next short-interest snapshot. The FINRA data used here covers publicly reported trades handled through certain FINRA facilities. It does not represent every short sale in the U.S. market.

### Failures to deliver

A failure to deliver, or FTD, occurs when shares are not delivered by the required settlement date.

The SEC data reports the total outstanding fail balance for a security on each settlement date. It is not a count of new failures created that day. FTDs can result from long or short transactions, so an FTD is not proof of naked short selling.

### Why the difference matters

These measures answer different questions:

| Measure | What it tells us |
|---|---|
| Short interest | How many short positions remain open at a reporting snapshot? |
| Daily short-sale volume | How much FINRA-reported short-sale activity occurred that day? |
| Failures to deliver | How many shares remained undelivered on a settlement date? |

A stock can therefore have high daily short-sale volume but modest short interest, or a large FTD balance without unusually high short activity. Treating the measures as interchangeable can lead to misleading conclusions.

## What I plan to investigate

The analysis will focus on four questions:

1. Do stocks with unusually high short-sale activity also have unusually high short interest?
2. Does a change in short-sale activity tend to appear before a change in reported short interest?
3. What do short interest and recent short activity look like when a stock has an extreme FTD balance?
4. What separates a one-day FTD spike from an FTD balance that persists across several settlement dates?

The goal is to measure these relationships, not assume they exist. A weak relationship or a null result would still be useful.

## Data

The project will use three free public regulatory datasets:

- FINRA Consolidated NMS Daily Short Sale Volume
- FINRA Equity Short Interest
- SEC Fails-to-Deliver Data

The target period begins in August 2018. Some questions may require a later start if one of the datasets does not have complete coverage for the full period. Missing history will not be treated as zero.

## Approach

PostgreSQL and SQL will handle the core data modeling, joins, rolling calculations, and episode construction. Python will be used for data checks, statistical analysis, and supporting charts. The completed analysis will be presented in Power BI.

This is a market-structure research project. It is not intended to predict prices, identify short squeezes, or produce trading signals.

## Project status

The source acquisition, PostgreSQL model, cleaning, security matching, short-volume features, and descriptive short-interest analysis are complete. Formal statistical inference and FTD analysis have not started.

## Getting the data

The three sources can be acquired with standard Python and no paid API keys:

```powershell
python -m src.ingestion.finra_short_volume
python -m src.ingestion.finra_short_interest
python -m src.ingestion.sec_ftd
```

Each command resumes safely when valid raw files already exist. Raw downloads are stored under `data/raw/` and are excluded from Git. Use `--help` to see date-range, worker, and smoke-test options.

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

Run the database assertions and query the quality report with:

```powershell
python -m src.cleaning.run --sql-dir sql/tests
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/003_cleaning_quality.sql'
```

To refresh only the quality, identity, and coverage summaries without rebuilding the large cleaned tables:

```powershell
python -m src.cleaning.run --summaries-only
```

Build the daily short-volume ratios and observation-window features with:

```powershell
python -m src.features.run
```

The feature table uses only valid rows with supported high- or medium-confidence identities. Rolling values require complete 5-, 14-, or 30-observation histories. Recent partial periods are kept for review but flagged out of the primary analysis window.

After the build, rerun the database assertions and inspect the feature quality reports with:

```powershell
python -m src.cleaning.run --sql-dir sql/tests
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/004_short_volume_features.sql'
```

## Short-interest cycle analysis

Build the short-interest cycles and align each observation with FINRA activity strictly before its settlement date:

```powershell
python -m src.analysis.run
```

The primary specification uses the preceding 14 observed FINRA trading days. Five- and 30-observation averages are retained as limited comparisons. Short-interest changes use adjacent reporting cycles, and rows after the latest complete shared month remain stored but are excluded from primary cohorts.

Run the assertions and descriptive report with:

```powershell
python -m src.cleaning.run --sql-dir sql/tests
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/005_short_interest_quality.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/006_short_interest_results.sql'
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /project-sql/validation/007_short_interest_sensitivity.sql'
```

The report contains descriptive correlations and fixed-cohort summaries only. Settlement dates are measurement dates; historical publication dates are unavailable, so these results are not a study of what investors knew at the time.

For the exchange-listed short-interest population, 97.68% of rows received a supported match. Daily short volume matched at 97.59%. Those figures include both exact same-date matches and lower-confidence matches inside an SEC-observed symbol date range; the report shows them separately. The 100% attached to SEC FTD rows only means each valid CUSIP anchors its own row—it is not a cross-source match rate.
