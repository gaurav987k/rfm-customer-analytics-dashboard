<div align="center">

# RFM Customer Analytics Dashboard

**End-to-end customer segmentation pipeline — from raw CSV files to an interactive Power BI dashboard**

![BigQuery](https://img.shields.io/badge/BigQuery-4285F4?style=for-the-badge&logo=googlebigquery&logoColor=white)
![Power BI](https://img.shields.io/badge/Power%20BI-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)
![SQL](https://img.shields.io/badge/SQL-336791?style=for-the-badge&logo=postgresql&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)

</div>

---

## Overview

This project segments **287 customers** from a print-on-demand business using the **RFM framework** — Recency, Frequency, Monetary. Raw transactional data from 12 monthly CSV files is ingested into Google BigQuery, scored with SQL window functions, and visualised in Power BI.

> **RFM** tells you which customers are your best, which are at risk of leaving, and which have already gone — using nothing but purchase history.

---

## Dashboard Preview

![Power BI Dashboard](Screenshot%202026-05-23%20194126.png)

> **287** total customers · **£17,069** total revenue · **6** product types · **Jan–Dec 2025**

---

## How RFM Works

| Dimension | Question | Scoring logic |
|-----------|----------|---------------|
| **R** ecency | How many days since last purchase? | Lower days → higher score |
| **F** requency | How many orders total? | More orders → higher score |
| **M** onetary | What is total lifetime spend? | Higher spend → higher score |

Each dimension is scored **1–10** using `NTILE(10)` percentile ranking. The three scores are summed into a **total score (3–30)** which maps to a named segment.

---

## Pipeline Architecture

```
202501.csv
202502.csv        ┌─────────────────────────────────────────────────────────┐
   ...      ───▶  │  STEP 1   STEP 2    STEP 3    STEP 4    STEP 5          │
202512.csv        │  Ingest ▶ Metrics ▶ Scores ▶  Total  ▶ Segments ──▶ 📊  │
                  └─────────────────────────────────────────────────────────┘
                      ↓          ↓          ↓         ↓          ↓
                  sales_2025  rfmmetrics rfmscores  rfm_total  rfm_segments
                  (TABLE)     (VIEW)     (VIEW)     (VIEW)     (VIEW → Power BI)
```

---

## SQL Pipeline — Step by Step

### Step 1 — Consolidate 12 monthly files

```sql
CREATE OR REPLACE TABLE `project.sales.sales_2025` AS

SELECT * FROM `project.sales.2025-1`
UNION ALL
SELECT * FROM `project.sales.2025-2`
UNION ALL
-- ... months 3–11 ...
UNION ALL
SELECT * EXCEPT(string_field_5, string_field_6, string_field_7)
FROM `project.sales.2025-12`;
```

> **Why `SELECT * EXCEPT` on December?** The December CSV was exported with 3 extra empty columns — a source schema anomaly. Without dropping them, `UNION ALL` fails with a schema mismatch. This is the only month that needs special treatment.

---

### Step 2 — Compute RFM metrics + ranks

```sql
CREATE OR REPLACE VIEW `project.sales.rfmmetrics` AS

WITH current_date AS (
  SELECT DATE('2026-03-06') AS analysis_date
),
rfm AS (
  SELECT
    CustomerID,
    MAX(OrderDate)                                        AS last_order_date,
    DATE_DIFF(analysis_date, MAX(OrderDate), DAY)         AS recency,
    COUNT(*)                                              AS frequency,
    SUM(OrderValue)                                       AS monetary
  FROM `project.sales.sales_2025`
  GROUP BY CustomerID
)
SELECT rfm.*,
  ROW_NUMBER() OVER (ORDER BY recency ASC)    AS r_rank,
  ROW_NUMBER() OVER (ORDER BY frequency DESC) AS f_rank,
  ROW_NUMBER() OVER (ORDER BY monetary DESC)  AS m_rank
FROM rfm;
```

> **Why `ROW_NUMBER()` not `RANK()`?** `RANK()` gives tied rows the same number, creating uneven bucket sizes when `NTILE` runs in the next step. `ROW_NUMBER()` guarantees every customer gets a unique rank so `NTILE(10)` always produces exactly equal groups.

---

### Step 3 — Assign decile scores (1–10)

```sql
CREATE OR REPLACE VIEW `project.sales.rfmscores` AS

SELECT *,
  NTILE(10) OVER (ORDER BY r_rank DESC) AS r_score,
  NTILE(10) OVER (ORDER BY f_rank DESC) AS f_score,
  NTILE(10) OVER (ORDER BY m_rank DESC) AS m_score
FROM `project.sales.rfmmetrics`;
```

> **Score 10 = best, 1 = worst.** `ORDER BY r_rank DESC` reverses the rank so that rank 1 (most recent) maps to bucket 10 (best score). The same logic applies to frequency and monetary.

---

### Step 4 — Total RFM score

```sql
CREATE OR REPLACE VIEW `project.sales.rfm_totalscores` AS

SELECT
  CustomerID,
  recency, frequency, monetary,
  r_score, f_score, m_score,
  (r_score + f_score + m_score) AS rfm_total_score
FROM `project.sales.rfmscores`
ORDER BY rfm_total_score DESC;
```

Score range: **3** (minimum: 1+1+1) → **30** (maximum: 10+10+10).

---

### Step 5 — Segment labels (BI-ready view)

```sql
CREATE OR REPLACE VIEW `project.sales.rfm_segments` AS

SELECT *,
  CASE
    WHEN rfm_total_score BETWEEN 25 AND 30 THEN 'Champions'
    WHEN rfm_total_score BETWEEN 20 AND 24 THEN 'Loyal Customers'
    WHEN rfm_total_score BETWEEN 15 AND 19 THEN 'Potential Loyalists'
    WHEN rfm_total_score BETWEEN 10 AND 14 THEN 'At Risk'
    WHEN rfm_total_score BETWEEN  5 AND  9 THEN 'Hibernating'
    ELSE                                        'Lost Customers'
  END AS customer_segment
FROM `project.sales.rfm_totalscores`
ORDER BY rfm_total_score DESC;
```

This view connects directly to Power BI — no further transformation needed.

---

## Customer Segments

| Segment | Score | Count | % | What it means |
|---------|:-----:|------:|:-:|---------------|
| 🏆 Champions | 25–30 | 52 | 18% | Bought recently, buy often, highest spenders |
| 💛 Loyal Customers | 20–24 | 44 | 15% | Regular buyers with strong lifetime value |
| 🌱 Potential Loyalists | 15–19 | 77 | 27% | Recent, engaged — largest growth opportunity |
| ⚠️ At Risk | 10–14 | 61 | 21% | Were good customers, starting to disengage |
| 💤 Hibernating | 5–9 | 40 | 14% | Low activity across all three dimensions |
| ❌ Lost Customers | 3–4 | 13 | 5% | No meaningful engagement remaining |

---

## Source Data

**994 orders · 287 customers · 6 products · Jan–Dec 2025**

| Field | Type | Description |
|-------|------|-------------|
| `OrderID` | STRING | Unique order identifier |
| `CustomerID` | STRING | Customer identifier (e.g. `CUST0001`) |
| `OrderDate` | DATE | Date of purchase |
| `ProductType` | STRING | Business Card, Canvas Print, Flyer, Greeting Card, Photo Book, Poster |
| `OrderValue` | FLOAT | Order revenue in GBP |

### Product revenue breakdown

| Product | Revenue | Orders | Avg order value |
|---------|--------:|-------:|----------------:|
| Canvas Print | £6,163 | 155 | £39.76 |
| Photo Book | £3,768 | 151 | £24.95 |
| Poster | £2,399 | 159 | £15.09 |
| Business Card | £2,144 | 178 | £12.04 |
| Flyer | £1,646 | 163 | £10.10 |
| Greeting Card | £950 | 188 | £5.05 |

> Canvas Print drives the most revenue despite not having the most orders — highest average order value by far.

---

## Project Structure

```
rfm-customer-analytics-dashboard/
│
├── data/
│   ├── 202501.csv          # Jan 2025 sales
│   ├── 202502.csv          # Feb 2025 sales
│   ├── ...
│   └── 202512.csv          # Dec 2025 sales (extra columns — handled in SQL)
│
├── wip.sql                 # Full BigQuery pipeline (all 5 steps)
├── go_rfm.pbix             # Power BI dashboard
├── README.md
└── LICENSE
```

---

## How to Run

### Prerequisites

- Google Cloud project with BigQuery enabled
- Power BI Desktop

### Steps

**1. Upload CSVs to BigQuery**

Upload each monthly CSV as a BigQuery table:

```
Dataset: sales
Table names: 2025-1, 2025-2, ..., 2025-12
```

**2. Update the project ID**

In `wip.sql`, replace every instance of `rfm-analysis-495207` with your GCP project ID.

**3. Run the SQL pipeline in BigQuery**

Execute `wip.sql` in order — each step depends on the previous:

```
Step 1 → creates table:  sales.sales_2025
Step 2 → creates view:   sales.rfmmetrics
Step 3 → creates view:   sales.rfmscores
Step 4 → creates view:   sales.rfm_totalscores
Step 5 → creates view:   sales.rfm_segments   ← Power BI connects here
```

**4. Connect Power BI**

Open `go_rfm.pbix` → refresh data source → point to your `rfm_segments` view.

---

## Tech Stack

| Tool | Purpose |
|------|---------|
| **Google BigQuery** | Cloud data warehouse — ingestion, SQL processing |
| **Standard SQL** | `UNION ALL`, CTEs, `ROW_NUMBER()`, `NTILE()`, `DATE_DIFF()` |
| **Power BI** | Interactive dashboard — KPI cards, donut chart, bar chart, customer table |

---

## Key SQL Concepts Used

- `UNION ALL` — combine 12 monthly tables without deduplication
- `SELECT * EXCEPT(...)` — BigQuery-specific syntax to drop schema anomaly columns
- `DATE_DIFF()` — calculate recency in days from a fixed snapshot date
- `ROW_NUMBER()` — assign unique ranks without ties (required for even NTILE buckets)
- `NTILE(10)` — percentile-based decile scoring, distribution-aware
- `CASE WHEN` — map numeric scores to human-readable segment labels
- CTE (`WITH`) — isolate the analysis date for easy future updates

---

## License

See [LICENSE](LICENSE).
