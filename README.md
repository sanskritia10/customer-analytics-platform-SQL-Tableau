# Customer Intelligence Platform

An end-to-end **Customer Intelligence Platform** built using **PostgreSQL, SQL, and Tableau** on the Olist Brazilian E-Commerce dataset.

The project demonstrates a complete analytics workflow from **business requirements and raw-data profiling through data quality assessment, data transformation, customer-level analytics, segmentation, and management reporting**.

The objective is to convert raw transactional data into actionable customer intelligence that supports strategic decisions around **customer value, retention, revenue concentration, and customer experience**.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Business Objectives](#business-objectives)
- [Dataset Architecture & Scale](#dataset-architecture--scale)
- [Project Workflow](#project-workflow)
- [Methodology & Technical Implementation](#methodology--technical-implementation)
  - [1. Business Requirements (BRD)](#1-business-requirements)
  - [2. Data Profiling](#2-data-profiling)
  - [3. Data Quality Assessment (DQA)](#3-data-quality-assessment)
  - [4. Medallion Architecture (Bronze–Silver–Gold)](#4-medallion-architecture-bronzesilvergold)
  - [5. Gold Analytical Layer](#5-gold-analytical-layer)
  - [6. Customer Intelligence & RFM Analysis](#6-customer-intelligence--rfm-analysis)
  - [7. Customer Segmentation](#7-customer-segmentation)
  - [8. Customer Type Analysis](#8-customer-type-analysis)
  - [9. Customer Experience Analysis](#9-customer-experience-analysis)
- [Key Business Insights & Strategy](#key-business-insights--strategy)
- [Tableau Dashboards](#tableau-dashboards)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Project Outcome](#project-outcome)

---

## Project Overview

In e-commerce, evaluating customer performance strictly on aggregate GMV masks critical retention risks and concentration vulnerabilities. This project implements a robust SQL data pipeline and analytics platform that establishes a single customer view (Customer 360), segments customer cohorts using RFM principles, and overlays delivery and customer experience metrics to identify high-impact growth and retention levers.

---

## Business Objectives

The analysis was designed to answer core business questions:
- **Customer Value & Identification:** Who are the highest-value customers across the platform?
- **Retention & Repeat Purchasing:** What proportion of customers make repeat purchases, and how much do they contribute to overall revenue?
- **Revenue Concentration:** How concentrated is platform revenue across customer spend tiers?
- **Retention Opportunities:** Which one-time buyers represent high-upside retention targets?
- **Service & Experience Risk:** Are high-value customers disproportionately impacted by logistics delays or poor review scores?
- **Strategic Prioritization:** Which specific customer segments require immediate executive and operational focus?

---

## Dataset Architecture & Scale

The project utilizes the **Olist Brazilian E-Commerce Public Dataset**, covering transactions from **September 2016 to October 2018**.

| Entity | Records | Description |
|---|---:|---|
| **Customers** | 99,441 | Customer account and location data |
| **Unique Customers** | 96,096 | Distinct underlying individuals (`customer_unique_id`) |
| **Orders** | 99,441 | Order transaction records and operational timestamps |
| **Order Items** | 112,650 | Product items, prices, and freight per order |
| **Payments** | 103,886 | Payment methods, installment structures, and values |
| **Products** | 32,951 | Product specifications, dimensions, and categories |
| **Reviews** | 99,224 | Customer review scores and feedback |
| **Sellers** | 3,095 | Merchant identity and location data |
| **Geolocation** | 19,015 | Zip code prefixes, coordinates, and state mapping |
| **Category Translations** | 71 | Portuguese-to-English category translation mapping |

---

## Project Workflow

```text
Business Requirements (BRD)
        ↓
Data Profiling & Relationship Discovery
        ↓
Data Quality Assessment (53 Validation Rules)
        ↓
Bronze Layer (Raw Schema & Ingestion)
        ↓
Silver Layer (Cleaned, Reconciled & Validated Entities)
        ↓
Gold Layer (Customer 360 & Analytical Views)
        ↓
Customer Analytics & RFM Scoring
        ↓
Behavioral Customer Segmentation
        ↓
Executive Insights & Strategic Recommendations
        ↓
Interactive Tableau Dashboards
```

---

## Methodology & Technical Implementation

### 1. Business Requirements

A formal Business Requirements Document (BRD) was created to establish KPIs, analytical models, segmentation logic, and data definitions prior to query execution.

*Reference:* `documentation/BRD_Customer_Intelligence.pdf`

---

### 2. Data Profiling

Initial profiling determined structural grains, foreign key relationships, null distributions, and anomalies:
- **Customer Identity Granularity:** Disambiguated `customer_id` (transactional session level) from `customer_unique_id` (individual customer level).
- **One-to-Many Relationships:** Handled multiple items per order and split payment structures requiring pre-aggregation before joining to order headers.
- **Logistics Anomalies:** Identified timestamp sequences requiring validation (e.g., carrier pick-up vs. approval dates).

*Reference:* `documentation/Data_Profiling_Report.pdf`

---

### 3. Data Quality Assessment

A comprehensive 53-rule Data Quality Assessment (DQA) audit was executed across all entities.

#### Key Findings & Quality Status

| Finding | Result | Operational Action |
|---|---:|---|
| Multiple `customer_id` per `customer_unique_id` | 2,997 | Reconciled via customer identity mapping in Silver layer |
| Duplicate Review IDs | 789 | Deduplicated preserving latest timestamp |
| Carrier timestamp prior to order approval | 1,359 | Flagged & normalized in transformation pipeline |
| Missing product categories | 610 | Assigned default `'unknown'` classification |
| Orders without line items | 775 | Excluded from item-level financial aggregations |
| Zero payment installments | 2 | Imputed / reconciled with payment records |
| Customer delivery recorded before carrier dispatch | 23 | Validated via sequential delivery business rules |
| Delivered orders missing delivery timestamp | 8 | Filtered out of logistics duration calculations |

*Reference:* `documentation/Data_Quality_Assessment.pdf`

---

### 4. Medallion Architecture (Bronze–Silver–Gold)

#### Bronze Layer

Ingests raw entities with complete fidelity, maintaining native source structures:

```text
bronze/
├── customers
├── orders
├── order_items
├── payments
├── products
├── sellers
├── reviews
├── geolocation
└── category_translation
```

#### Silver Layer

Transforms raw tables into cleaned, conformed, and analysis-ready structures:
- Resolves customer identity levels across multi-purchase accounts.
- Pre-aggregates order items and split payments to the exact order grain.
- Derives standardized logistics metrics: `delivery_duration_days`, `is_late_order`, and delivery window variance.
- Standardizes product taxonomy and category translations.

**Silver Layer Validation Metrics:**

| Metric | Result |
|---|---:|
| Total Orders Processed | 99,441 |
| Unique Customers | 96,096 |
| Valid Delivery Records | 96,476 |
| Negative Delivery Durations | 0 (Pass) |
| Minimum Delivery Duration | 0.53 days |
| Maximum Delivery Duration | 209.63 days |
| Average Delivery Duration | 12.56 days |

---

### 5. Gold Analytical Layer

The Gold layer provides clean dimensional models, curated fact tables, and optimized views:
- `gold.customer_360` — Comprehensive single customer view.
- `gold.customer_intelligence` — Behavioral and monetary metrics.
- `gold.customer_experience` — Logistics performance and review scoring per customer.
- `gold.order_summary` — Reconciled order-level fact table.
- `gold.executive_kpis` — Aggregate platform-level metrics.
- `gold.v_customer_segments` — Dynamic customer segmentation view.
- `gold.v_customer_type_performance` — One-time vs. Repeat customer performance.
- `gold.v_retention_opportunities` — Target list for high-value win-back campaigns.
- `gold.v_revenue_concentration` — Spend quintile and distribution model.

---

### 6. Customer Intelligence & RFM Analysis

Customers were scored across three core behavioral dimensions:
- **Recency ($R$):** Days since most recent completed order.
- **Frequency ($F$):** Total count of completed orders.
- **Monetary Value ($M$):** Total lifetime spend across all orders.

#### Customer Spend Distribution

| Metric | Value ($/R$) |
|---|---:|
| Minimum | 0.00 |
| 25th Percentile | 63.12 |
| Median (50th Percentile) | 108.00 |
| 75th Percentile | 183.53 |
| 90th Percentile | 319.57 |
| 95th Percentile | 476.15 |
| Maximum | 13,664.08 |

#### Monetary Quintile Distribution

| Quintile | Customers | Revenue Share |
|---|---:|---:|
| **Quintile 1 (Lowest 20%)** | 19,220 | 4.77% |
| **Quintile 2** | 19,219 | 8.49% |
| **Quintile 3** | 19,219 | 13.06% |
| **Quintile 4** | 19,219 | 19.91% |
| **Quintile 5 (Top 20%)** | 19,219 | **53.77%** |

> **Key Takeaway:** The top 20% of customers generate **53.77%** of total platform revenue, highlighting strong Pareto dynamics and extreme revenue concentration.

---

### 7. Customer Segmentation

Customer behavior was synthesized into 6 business segments based on purchase recency, order frequency, and cumulative customer value:

| Customer Segment | Customers | % of Customer Base | Total Revenue ($/R$) | % Revenue Share | Avg Customer Value ($/R$) |
|---|---:|---:|---:|---:|---:|
| **High-Value One-Time** | 36,055 | 37.52% | 10,911,288.75 | **68.16%** | 302.63 |
| **Established One-Time** | 18,978 | 19.75% | 1,642,328.02 | 10.26% | 86.54 |
| **Recent One-Time** | 22,311 | 23.22% | 1,632,042.84 | 10.19% | 73.15 |
| **High-Value Repeat** | 2,383 | 2.48% | 883,758.38 | 5.52% | **370.86** |
| **Low-Value Inactive** | 15,755 | 16.40% | 879,189.80 | 5.49% | 55.80 |
| **Developing Repeat** | 614 | 0.64% | 60,264.33 | 0.38% | 98.14 |
| **Total** | **96,096** | **100.00%** | **16,008,872.12** | **100.00%** | **166.59** |

---

### 8. Customer Type Analysis

| Customer Type | Customers | Customer % | Total Revenue ($/R$) | Revenue % | Avg Customer Value ($/R$) |
|---|---:|---:|---:|---:|---:|
| **One-Time Customer** | 93,099 | 96.88% | 15,064,849.41 | 94.10% | 161.82 |
| **Repeat Customer** | 2,997 | 3.12% | 944,022.71 | 5.90% | **314.99** |

- Repeat customers deliver **~2x higher average monetary value** ($314.99 vs. $161.82) compared to one-time buyers.
- Despite representing just 3.12% of the user base, repeat buyers form the bedrock of sustainable customer lifetime value.

---

### 9. Customer Experience Analysis

Cross-referencing customer value segments against operational experience KPIs revealed that high-value relationships face notable service delivery friction.

#### Customer Type Experience Comparison

| Customer Type | Avg Delivery Days | Late Order Rate (%) | Avg Review Score | Poor Experience Rate (%) |
|---|---:|---:|---:|---:|
| **One-Time** | 12.58 | 6.84% | 4.08 | 4.07% |
| **Repeat** | 12.34 | 5.84% | 4.12 | 6.27% |

#### Segment-Level Logistics & Experience Metrics

| Segment | Avg Delivery Days | Late Order Rate (%) | Avg Review Score | Poor Experience Rate (%) |
|---|---:|---:|---:|---:|
| **High-Value Repeat** | 12.71 | 6.18% | 4.10 | **6.63%** |
| **High-Value One-Time** | 13.73 | 7.59% | 4.00 | 4.62% |
| **Developing Repeat** | 10.92 | 4.52% | 4.18 | 4.89% |
| **Established One-Time** | 13.95 | 7.71% | 4.05 | 4.94% |
| **Recent One-Time** | 9.99 | 6.36% | 4.21 | 3.51% |
| **Low-Value Inactive** | 11.98 | 4.76% | 4.14 | 2.54% |

---

## Key Business Insights & Strategy

1. **Low Repeat Purchase Penetration (3.12%):**
   - 96.88% of customers churn after a single purchase.
   - *Recommendation:* Introduce targeted post-purchase reactivation triggers within 30–60 days of initial order fulfillment.
2. **Severe Revenue Concentration:**
   - The top 20% of spenders account for 53.77% of total revenue.
   - *Recommendation:* Prioritize VIP retention workflows and dedicated account recovery protocols for top-tier spenders.
3. **Massive Upside in High-Value One-Time Segment:**
   - 36,055 customers in the **High-Value One-Time** segment drove **68.16% of total platform revenue** ($10.9M+).
   - *Recommendation:* Converting even 3–5% of this segment into repeat buyers represents a major multi-million dollar revenue expansion opportunity.
4. **Service Friction Among Most Valuable Buyers:**
   - **High-Value Repeat** customers suffer from the highest poor-experience rate (**6.63%**) and **High-Value One-Time** buyers experience the highest late order rate (**7.59%**).
   - *Recommendation:* Implement proactive customer support outreach for high-value orders experiencing delivery delays before negative reviews are registered.

---

## Tableau Dashboards

The analytical layer powers three interactive Tableau executive dashboards:

### Dashboard 1 — Executive Overview

- Top-line KPIs: Total Customers, Total Revenue, Repeat Customer %, AOV, Platform Avg Delivery Days, and Review Scores.
- Monthly revenue trends, order volume trajectory, and overall fulfillment health.

### Dashboard 2 — Customer Value & Segmentation

- RFM quintile breakdowns and Pareto revenue distribution curves.
- Customer segment matrix mapping customer volume vs. monetary contribution.
- Segment-level migration and retention opportunity funnels.

### Dashboard 3 — Customer Experience & Logistics

- Correlation analysis between delivery delay thresholds and customer review degradation.
- Late-order rate heatmaps across Brazilian states and carrier routes.
- Segment-specific customer satisfaction (CSAT) and poor-experience risk profiling.

*Dashboard previews are available in `tableau/dashboard_screenshots/`.*

---

## Technology Stack

- **Relational Database:** PostgreSQL
- **SQL & Data Modeling:** Common Table Expressions (CTEs), Window Functions (`NTILE`, `ROW_NUMBER`, `DENSE_RANK`), Advanced Aggregations, Conditional Logic (`CASE`), Dimensional Modeling
- **Business Intelligence & Visualization:** Tableau Desktop / Tableau Public
- **Data Architecture:** Medallion Architecture (Bronze $
ightarrow$ Silver $
ightarrow$ Gold)
- **Data Source:** Olist Brazilian E-Commerce Dataset (Kaggle)

---

## Repository Structure

```text
customer-intelligence-platform/
│
├── README.md                                <- Main project documentation
│
├── documentation/                           <- Detailed analytical & requirements documentation
│   ├── BRD_Customer_Intelligence.pdf        <- Business Requirements Document
│   ├── Data_Profiling_Report.pdf            <- Source Data Profiling Report
│   ├── Data_Quality_Assessment.pdf          <- 53-rule DQA Report & Audit Logs
│   └── Customer_Intelligence_Analysis.pdf   <- Deep-dive Analytical Findings
│
├── sql/                                     <- SQL Scripts (PostgreSQL)
│   ├── 01_bronze_setup.sql                  <- Raw table schemas & data ingestion
│   ├── 02_data_profiling.sql                <- Profiling queries & structural checks
│   ├── 03_data_quality_assessment.sql       <- 53 DQ test scripts
│   ├── 04_silver_layer.sql                  <- Cleaning, reconciliation & validation logic
│   └── 05_gold_layer.sql                    <- Customer 360, RFM & analytical views
│
└── tableau/                                 <- Visualization assets
    └── dashboard_screenshots/               <- Exported dashboard views & visual guides
```

---

## Project Outcome

This platform demonstrates how structured analytics and data engineering transform raw transactional records into actionable customer intelligence:
1. **Engineered an enterprise Medallion pipeline** processing ~100k orders with automated data quality gates.
2. **Constructed a comprehensive Customer 360 profile** capturing recency, frequency, monetary value, and customer experience metrics.
3. **Delivered executive-ready Tableau dashboards** that reveal revenue concentration risks and high-upside retention targets.

---

### Dataset Attribution

- **Dataset:** [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) hosted on Kaggle.
- *Note:* This project is created for portfolio and analytics demonstration purposes.
