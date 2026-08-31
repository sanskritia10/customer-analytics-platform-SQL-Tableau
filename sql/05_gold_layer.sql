/*====================================================================
  05_GOLD_LAYER.SQL
  Project: Customer Intelligence Platform
  Dataset: Olist Brazilian E-commerce Dataset
  Layer: Gold

  Purpose:
    Build business-ready dimensional and aggregate analytical datasets:
      1. gold.order_summary                 -> Order-grain analytical table
      2. gold.customer_360                  -> Customer-grain base table
      3. gold.customer_category_behavior    -> Customer x Category behavior
      4. gold.customer_experience           -> Customer satisfaction & delivery
      5. gold.customer_intelligence         -> RFM scoring & segmentation
      6. gold.executive_kpis                -> Single-row business summary
      7. Management Reporting Views          -> Segment, retention & risk views
      8. Post-Build Integrity Validation    -> Layer validation assertions
====================================================================*/

-- -------------------------------------------------------------------
-- 0. Schema Initialization
-- -------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS gold;

-- -------------------------------------------------------------------
-- 1. Order Summary (Grain: one row per order_id)
-- -------------------------------------------------------------------
DROP TABLE IF EXISTS gold.order_summary CASCADE;

CREATE TABLE gold.order_summary AS
WITH item_summary AS (
    SELECT
        order_id,
        COUNT(*) AS total_items,
        COUNT(DISTINCT product_id) AS distinct_products,
        COUNT(DISTINCT seller_id) AS distinct_sellers,
        SUM(price) AS merchandise_value,
        SUM(freight_value) AS freight_value,
        SUM(item_total_value) AS order_item_value,
        AVG(price) AS average_item_price,
        MAX(price) AS maximum_item_price
    FROM silver.order_items
    GROUP BY order_id
),
payment_summary AS (
    SELECT
        order_id,
        COUNT(*) AS payment_records,
        SUM(payment_value) AS total_payment_value,
        AVG(payment_value) AS average_payment_value,
        MAX(payment_value) AS maximum_payment_value,
        MAX(payment_installments) AS maximum_installments,
        COUNT(*) FILTER (WHERE payment_type = 'credit_card') AS credit_card_payment_records,
        COUNT(*) FILTER (WHERE payment_type = 'boleto') AS boleto_payment_records,
        COUNT(*) FILTER (WHERE payment_type = 'voucher') AS voucher_payment_records,
        COUNT(*) FILTER (WHERE payment_type = 'debit_card') AS debit_card_payment_records
    FROM silver.payments
    GROUP BY order_id
),
review_summary AS (
    SELECT
        order_id,
        COUNT(*) AS review_count,
        ROUND(AVG(review_score), 2) AS average_review_score,
        COUNT(*) FILTER (WHERE review_score <= 2) AS low_score_reviews,
        COUNT(*) FILTER (WHERE review_score >= 4) AS high_score_reviews,
        COUNT(*) FILTER (WHERE review_comment_message IS NOT NULL) AS reviews_with_message
    FROM silver.reviews
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    o.delivery_days,
    o.delivery_vs_estimate_days,
    CASE
        WHEN o.delivery_vs_estimate_days > 0 THEN TRUE
        WHEN o.delivery_vs_estimate_days IS NOT NULL THEN FALSE
        ELSE NULL
    END AS delivered_late,
    o.approval_carrier_timestamp_anomaly,
    o.delivery_sequence_anomaly,
    COALESCE(i.total_items, 0) AS total_items,
    COALESCE(i.distinct_products, 0) AS distinct_products,
    COALESCE(i.distinct_sellers, 0) AS distinct_sellers,
    COALESCE(i.merchandise_value, 0) AS merchandise_value,
    COALESCE(i.freight_value, 0) AS freight_value,
    COALESCE(i.order_item_value, 0) AS order_item_value,
    i.average_item_price,
    i.maximum_item_price,
    COALESCE(p.payment_records, 0) AS payment_records,
    COALESCE(p.total_payment_value, 0) AS total_payment_value,
    p.average_payment_value,
    p.maximum_payment_value,
    p.maximum_installments,
    COALESCE(p.credit_card_payment_records, 0) AS credit_card_payment_records,
    COALESCE(p.boleto_payment_records, 0) AS boleto_payment_records,
    COALESCE(p.voucher_payment_records, 0) AS voucher_payment_records,
    COALESCE(p.debit_card_payment_records, 0) AS debit_card_payment_records,
    COALESCE(r.review_count, 0) AS review_count,
    r.average_review_score,
    COALESCE(r.low_score_reviews, 0) AS low_score_reviews,
    COALESCE(r.high_score_reviews, 0) AS high_score_reviews,
    COALESCE(r.reviews_with_message, 0) AS reviews_with_message
FROM silver.orders o
LEFT JOIN item_summary i ON o.order_id = i.order_id
LEFT JOIN payment_summary p ON o.order_id = p.order_id
LEFT JOIN review_summary r ON o.order_id = r.order_id;
CREATE UNIQUE INDEX idx_gold_order_summary_order_id ON gold.order_summary(order_id);
CREATE INDEX idx_gold_order_summary_customer_id ON gold.order_summary(customer_id);

-- -------------------------------------------------------------------
-- 2. Customer 360 (Grain: one row per customer_unique_id)
-- -------------------------------------------------------------------
DROP TABLE IF EXISTS gold.customer_360 CASCADE;

CREATE TABLE gold.customer_360 AS
WITH customer_accounts AS (
    SELECT DISTINCT customer_id, customer_unique_id
    FROM silver.customers
),
customer_orders AS (
    SELECT ca.customer_unique_id, os.*
    FROM customer_accounts ca
    INNER JOIN gold.order_summary os ON ca.customer_id = os.customer_id
),
customer_summary AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS total_orders,
        COUNT(DISTINCT order_id) FILTER (WHERE order_status = 'delivered') AS delivered_orders,
        COUNT(DISTINCT order_id) FILTER (WHERE order_status IN ('canceled', 'unavailable')) AS unsuccessful_orders,
        SUM(total_items) AS total_items,
        SUM(distinct_products) AS product_instances,
        SUM(order_item_value) AS total_merchandise_value,
        SUM(total_payment_value) AS total_payment_value,
        ROUND(AVG(total_payment_value), 2) AS average_order_value,
        MAX(total_payment_value) AS maximum_order_value,
        SUM(freight_value) AS total_freight_value,
        MIN(order_purchase_timestamp) AS first_purchase_timestamp,
        MAX(order_purchase_timestamp) AS last_purchase_timestamp,
        AVG(delivery_days) AS average_delivery_days,
        AVG(delivery_vs_estimate_days) AS average_delivery_vs_estimate_days,
        COUNT(*) FILTER (WHERE delivered_late = TRUE) AS late_orders,
        COUNT(*) FILTER (WHERE delivery_days IS NOT NULL) AS orders_with_delivery_data,
        SUM(review_count) AS total_reviews,
        AVG(average_review_score) FILTER (WHERE average_review_score IS NOT NULL) AS average_review_score,
        SUM(low_score_reviews) AS low_score_reviews,
        SUM(high_score_reviews) AS high_score_reviews,
        SUM(payment_records) AS total_payment_records,
        SUM(credit_card_payment_records) AS credit_card_payments,
        SUM(boleto_payment_records) AS boleto_payments,
        SUM(voucher_payment_records) AS voucher_payments,
        SUM(debit_card_payment_records) AS debit_card_payments,
        AVG(maximum_installments) AS average_max_installments
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    cs.customer_unique_id,
    customer_profile.customer_city,
    customer_profile.customer_state,
    customer_profile.customer_zip_code_prefix,
    cs.total_orders,
    cs.delivered_orders,
    cs.unsuccessful_orders,
    cs.total_items,
    cs.product_instances,
    cs.total_merchandise_value,
    cs.total_payment_value,
    cs.average_order_value,
    cs.maximum_order_value,
    cs.total_freight_value,
    cs.first_purchase_timestamp,
    cs.last_purchase_timestamp,
    EXTRACT(DAY FROM (cs.last_purchase_timestamp - cs.first_purchase_timestamp)) AS customer_activity_days,
    CASE WHEN cs.total_orders >= 2 THEN TRUE ELSE FALSE END AS repeat_customer,
    CASE
        WHEN EXTRACT(DAY FROM (cs.last_purchase_timestamp - cs.first_purchase_timestamp)) > 0
        THEN cs.total_orders / (EXTRACT(DAY FROM (cs.last_purchase_timestamp - cs.first_purchase_timestamp)) / 30.0)
        ELSE NULL
    END AS orders_per_month,
    cs.average_delivery_days,
    cs.average_delivery_vs_estimate_days,
    cs.late_orders,
    cs.orders_with_delivery_data,
    CASE
        WHEN cs.orders_with_delivery_data > 0 THEN cs.late_orders::NUMERIC / cs.orders_with_delivery_data
        ELSE NULL
    END AS late_order_rate,
    cs.total_reviews,
    cs.average_review_score,
    cs.low_score_reviews,
    cs.high_score_reviews,
    CASE
        WHEN cs.total_reviews > 0 THEN cs.low_score_reviews::NUMERIC / cs.total_reviews
        ELSE NULL
    END AS low_review_rate,
    cs.total_payment_records,
    cs.credit_card_payments,
    cs.boleto_payments,
    cs.voucher_payments,
    cs.debit_card_payments,
    cs.average_max_installments,
    CASE
        WHEN cs.credit_card_payments >= GREATEST(cs.boleto_payments, cs.voucher_payments, cs.debit_card_payments) THEN 'credit_card'
        WHEN cs.boleto_payments >= GREATEST(cs.credit_card_payments, cs.voucher_payments, cs.debit_card_payments) THEN 'boleto'
        WHEN cs.voucher_payments >= GREATEST(cs.credit_card_payments, cs.boleto_payments, cs.debit_card_payments) THEN 'voucher'
        ELSE 'debit_card'
    END AS primary_payment_method
FROM customer_summary cs
LEFT JOIN LATERAL (
    SELECT c.customer_city, c.customer_state, c.customer_zip_code_prefix
    FROM silver.customers c
    INNER JOIN gold.order_summary os ON c.customer_id = os.customer_id
    WHERE c.customer_unique_id = cs.customer_unique_id
    ORDER BY os.order_purchase_timestamp DESC
    LIMIT 1
) customer_profile ON TRUE;

CREATE UNIQUE INDEX idx_customer_360_unique_id ON gold.customer_360(customer_unique_id);
CREATE INDEX idx_customer_360_state ON gold.customer_360(customer_state);

-- -------------------------------------------------------------------
-- 3. Customer Category Behavior (Grain: customer_unique_id x category)
-- -------------------------------------------------------------------
DROP TABLE IF EXISTS gold.customer_category_behavior CASCADE;

CREATE TABLE gold.customer_category_behavior AS
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        oi.order_id,
        oi.product_id,
        p.product_category_name,
        p.product_category_name_english,
        oi.price,
        oi.freight_value
    FROM silver.order_items oi
    INNER JOIN silver.orders o ON oi.order_id = o.order_id
    INNER JOIN silver.customers c ON o.customer_id = c.customer_id
    LEFT JOIN silver.products p ON oi.product_id = p.product_id
),
category_summary AS (
    SELECT
        customer_unique_id,
        COALESCE(product_category_name_english, 'unknown') AS product_category,
        COUNT(DISTINCT order_id) AS category_orders,
        COUNT(*) AS category_items,
        COUNT(DISTINCT product_id) AS distinct_products,
        SUM(price) AS category_merchandise_value,
        SUM(freight_value) AS category_freight_value,
        AVG(price) AS average_item_price
    FROM customer_orders
    GROUP BY customer_unique_id, COALESCE(product_category_name_english, 'unknown')
)
SELECT
    customer_unique_id,
    product_category,
    category_orders,
    category_items,
    distinct_products,
    category_merchandise_value,
    category_freight_value,
    ROUND(average_item_price, 2) AS average_item_price,
    RANK() OVER (
        PARTITION BY customer_unique_id
        ORDER BY category_merchandise_value DESC
    ) AS category_value_rank,
    ROUND(category_merchandise_value / NULLIF(SUM(category_merchandise_value) OVER (PARTITION BY customer_unique_id), 0), 2) AS category_spend_share,
    ROUND(category_orders::NUMERIC / NULLIF(SUM(category_orders) OVER (PARTITION BY customer_unique_id), 0), 2) AS category_order_share
FROM category_summary;

CREATE INDEX idx_customer_category_customer ON gold.customer_category_behavior(customer_unique_id);
CREATE INDEX idx_customer_category_category ON gold.customer_category_behavior(product_category);

-- -------------------------------------------------------------------
-- 4. Customer Experience (Grain: one row per customer_unique_id)
-- -------------------------------------------------------------------
DROP TABLE IF EXISTS gold.customer_experience CASCADE;

CREATE TABLE gold.customer_experience AS
WITH customer_accounts AS (
    SELECT DISTINCT customer_id, customer_unique_id
    FROM silver.customers
),
customer_orders AS (
    SELECT
        ca.customer_unique_id,
        os.order_id,
        os.order_status,
        os.delivery_days,
        os.delivery_vs_estimate_days,
        os.delivered_late,
        os.average_item_price,
        os.average_payment_value,
        os.review_count,
        os.average_review_score,
        os.low_score_reviews,
        os.high_score_reviews
    FROM customer_accounts ca
    INNER JOIN gold.order_summary os ON ca.customer_id = os.customer_id
),
experience_summary AS (
    SELECT
        customer_unique_id,
        COUNT(*) FILTER (WHERE delivery_days IS NOT NULL) AS orders_with_delivery_data,
        AVG(delivery_days) FILTER (WHERE delivery_days IS NOT NULL) AS average_delivery_days,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days) FILTER (WHERE delivery_days IS NOT NULL) AS median_delivery_days,
        COUNT(*) FILTER (WHERE delivered_late = TRUE) AS late_orders,
        AVG(delivery_vs_estimate_days) FILTER (WHERE delivery_vs_estimate_days IS NOT NULL) AS average_delivery_vs_estimate_days,
        SUM(review_count) AS total_reviews,
        AVG(average_review_score) FILTER (WHERE average_review_score IS NOT NULL) AS average_review_score,
        SUM(low_score_reviews) AS low_score_reviews,
        SUM(high_score_reviews) AS high_score_reviews
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    customer_unique_id,
    orders_with_delivery_data,
    average_delivery_days,
    median_delivery_days,
    late_orders,
    ROUND(CASE
        WHEN orders_with_delivery_data > 0 THEN late_orders::NUMERIC / orders_with_delivery_data
        ELSE NULL
    END, 2) AS late_order_rate,
    ROUND(average_delivery_vs_estimate_days, 2) AS average_delivery_vs_estimate_days,
    total_reviews,
    ROUND(average_review_score, 2) AS average_review_score,
    low_score_reviews,
    high_score_reviews,
    ROUND(CASE
        WHEN total_reviews > 0 THEN low_score_reviews::NUMERIC / total_reviews
        ELSE NULL
    END, 2) AS low_review_rate,
    CASE WHEN late_orders > 0 THEN TRUE ELSE FALSE END AS has_delivery_delay,
    CASE WHEN low_score_reviews > 0 THEN TRUE ELSE FALSE END AS has_low_rating,
    CASE WHEN late_orders > 0 AND low_score_reviews > 0 THEN TRUE ELSE FALSE END AS poor_experience_flag
FROM experience_summary;

CREATE UNIQUE INDEX idx_customer_experience_customer ON gold.customer_experience(customer_unique_id);

-- -------------------------------------------------------------------
-- 5. Customer Intelligence (RFM Scoring & Segmentation)
-- -------------------------------------------------------------------
DROP TABLE IF EXISTS gold.customer_intelligence CASCADE;

CREATE TABLE gold.customer_intelligence AS
WITH analysis_date AS (
    SELECT MAX(last_purchase_timestamp)::DATE + 1 AS analysis_date
    FROM gold.customer_360
),
customer_base AS (
    SELECT
        c.customer_unique_id,
        a.analysis_date,
        (a.analysis_date - c.last_purchase_timestamp::DATE) AS recency_days,
        c.total_orders AS frequency,
        c.total_payment_value AS monetary_value,
        c.delivered_orders,
        c.average_order_value,
        c.repeat_customer,
        c.customer_state,
        c.last_purchase_timestamp
    FROM gold.customer_360 c
    CROSS JOIN analysis_date a
),
rfm_scored AS (
    SELECT
        cb.*,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS recency_score,
        NTILE(5) OVER (ORDER BY frequency) AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary_value) AS monetary_score,
        NTILE(5) OVER (ORDER BY monetary_value) AS monetary_quintile,
        6 - NTILE(5) OVER (ORDER BY recency_days) AS recency_quintile
    FROM customer_base cb
),
segmented AS (
    SELECT
        rs.*,
        (recency_score + frequency_score + monetary_score) AS rfm_score,
        CONCAT(recency_score, frequency_score, monetary_score) AS rfm_code,
        CASE
            WHEN frequency >= 2 AND monetary_quintile >= 4 THEN 'High-Value Repeat'
            WHEN frequency >= 2 THEN 'Developing Repeat'
            WHEN frequency = 1 AND monetary_quintile >= 4 THEN 'High-Value One-Time'
            WHEN frequency = 1 AND recency_quintile >= 4 THEN 'Recent One-Time'
            WHEN frequency = 1 AND monetary_quintile <= 2 AND recency_quintile <= 2 THEN 'Low-Value Inactive'
            ELSE 'Established One-Time'
        END AS customer_segment
    FROM rfm_scored rs
)
SELECT
    customer_unique_id,
    analysis_date,
    customer_state,
    last_purchase_timestamp,
    recency_days,
    frequency,
    monetary_value,
    recency_score,
    frequency_score,
    monetary_score,
    rfm_score,
    rfm_code,
    recency_quintile,
    monetary_quintile,
    repeat_customer,
    delivered_orders,
    average_order_value,
    customer_segment
FROM segmented;

CREATE UNIQUE INDEX idx_customer_intelligence_customer ON gold.customer_intelligence(customer_unique_id);
CREATE INDEX idx_customer_intelligence_segment ON gold.customer_intelligence(customer_segment);

-- -------------------------------------------------------------------
-- 6. Executive KPI Table (Grain: single row)
-- -------------------------------------------------------------------
DROP TABLE IF EXISTS gold.executive_kpis CASCADE;

CREATE TABLE gold.executive_kpis AS
SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE ci.frequency > 1) AS repeat_customers,
    COUNT(*) FILTER (WHERE ci.frequency = 1) AS one_time_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ci.frequency > 1) / NULLIF(COUNT(*), 0), 2) AS repeat_customer_rate,
    SUM(ci.frequency) AS total_orders,
    ROUND(SUM(ci.monetary_value)::numeric, 2) AS total_revenue,
    ROUND((SUM(ci.monetary_value) / NULLIF(SUM(ci.frequency), 0))::numeric, 2) AS average_order_value,
    ROUND(AVG(ci.monetary_value)::numeric, 2) AS average_customer_value,
    ROUND(SUM(ci.monetary_value) FILTER (WHERE ci.frequency > 1)::numeric, 2) AS repeat_customer_revenue,
    ROUND(100.0 * SUM(ci.monetary_value) FILTER (WHERE ci.frequency > 1) / NULLIF(SUM(ci.monetary_value), 0), 2) AS repeat_customer_revenue_share,
    ROUND(AVG(ce.average_delivery_days)::numeric, 2) AS average_delivery_days,
    ROUND((AVG(ce.late_order_rate) * 100)::numeric, 2) AS average_late_order_rate_pct,
    ROUND(AVG(ce.average_review_score)::numeric, 2) AS average_review_score,
    ROUND((100.0 * AVG(CASE WHEN ce.poor_experience_flag = TRUE THEN 1.0 ELSE 0.0 END))::numeric, 2) AS poor_experience_rate_pct
FROM gold.customer_intelligence ci
LEFT JOIN gold.customer_experience ce ON ci.customer_unique_id = ce.customer_unique_id;

-- -------------------------------------------------------------------
-- 7. Management Views
-- -------------------------------------------------------------------

-- Customer Segment Economics
CREATE OR REPLACE VIEW gold.v_customer_segments AS
SELECT
    ci.customer_segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_percentage,
    ROUND(SUM(ci.monetary_value)::numeric, 2) AS total_revenue,
    ROUND(100.0 * SUM(ci.monetary_value) / SUM(SUM(ci.monetary_value)) OVER (), 2) AS revenue_percentage,
    ROUND(AVG(ci.monetary_value)::numeric, 2) AS average_customer_value,
    ROUND(AVG(ci.frequency)::numeric, 2) AS average_orders,
    ROUND((SUM(ci.monetary_value) / NULLIF(SUM(ci.frequency), 0))::numeric, 2) AS average_order_value,
    ROUND(AVG(ci.recency_days)::numeric, 1) AS average_recency_days
FROM gold.customer_intelligence ci
GROUP BY ci.customer_segment
ORDER BY total_revenue DESC;

-- One-Time vs Repeat Performance
CREATE OR REPLACE VIEW gold.v_customer_type_performance AS
SELECT
    CASE WHEN ci.frequency > 1 THEN 'Repeat customer' ELSE 'One-time customer' END AS customer_type,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_percentage,
    ROUND(SUM(ci.monetary_value)::numeric, 2) AS total_revenue,
    ROUND(100.0 * SUM(ci.monetary_value) / SUM(SUM(ci.monetary_value)) OVER (), 2) AS revenue_percentage,
    ROUND(AVG(ci.monetary_value)::numeric, 2) AS average_customer_value,
    ROUND(AVG(ci.frequency)::numeric, 2) AS average_orders,
    ROUND((SUM(ci.monetary_value) / NULLIF(SUM(ci.frequency), 0))::numeric, 2) AS average_order_value
FROM gold.customer_intelligence ci
GROUP BY CASE WHEN ci.frequency > 1 THEN 'Repeat customer' ELSE 'One-time customer' END
ORDER BY total_revenue DESC;

-- Revenue Concentration by Monetary Quintile
CREATE OR REPLACE VIEW gold.v_revenue_concentration AS
WITH customer_quintiles AS (
    SELECT customer_unique_id, monetary_value, NTILE(5) OVER (ORDER BY monetary_value) AS monetary_quintile
    FROM gold.customer_intelligence
)
SELECT
    monetary_quintile,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_percentage,
    ROUND(MIN(monetary_value)::numeric, 2) AS minimum_customer_value,
    ROUND(MAX(monetary_value)::numeric, 2) AS maximum_customer_value,
    ROUND(AVG(monetary_value)::numeric, 2) AS average_customer_value,
    ROUND(SUM(monetary_value)::numeric, 2) AS total_revenue,
    ROUND(100.0 * SUM(monetary_value) / SUM(SUM(monetary_value)) OVER (), 2) AS revenue_percentage
FROM customer_quintiles
GROUP BY monetary_quintile
ORDER BY monetary_quintile;

-- Customer Experience by Segment
CREATE OR REPLACE VIEW gold.v_customer_experience AS
SELECT
    ci.customer_segment,
    COUNT(*) AS customers,
    ROUND(AVG(ce.average_delivery_days)::numeric, 2) AS average_delivery_days,
    ROUND((AVG(ce.late_order_rate) * 100)::numeric, 2) AS average_late_order_rate_pct,
    ROUND(AVG(ce.average_review_score)::numeric, 2) AS average_review_score,
    ROUND((100.0 * AVG(CASE WHEN ce.poor_experience_flag = TRUE THEN 1.0 ELSE 0.0 END))::numeric, 2) AS poor_experience_rate_pct
FROM gold.customer_intelligence ci
JOIN gold.customer_experience ce ON ci.customer_unique_id = ce.customer_unique_id
GROUP BY ci.customer_segment
ORDER BY average_review_score ASC;

-- Retention Opportunities for High-Priority Segments
CREATE OR REPLACE VIEW gold.v_retention_opportunities AS
SELECT
    ci.customer_segment,
    COUNT(*) AS customers,
    ROUND(SUM(ci.monetary_value)::numeric, 2) AS associated_revenue,
    ROUND(AVG(ci.monetary_value)::numeric, 2) AS average_customer_value,
    ROUND(AVG(ci.frequency)::numeric, 2) AS average_orders,
    ROUND(AVG(ci.recency_days)::numeric, 1) AS average_recency_days,
    ROUND(AVG(ce.average_delivery_days)::numeric, 2) AS average_delivery_days,
    ROUND((AVG(ce.late_order_rate) * 100)::numeric, 2) AS average_late_order_rate_pct,
    ROUND(AVG(ce.average_review_score)::numeric, 2) AS average_review_score,
    ROUND((100.0 * AVG(CASE WHEN ce.poor_experience_flag = TRUE THEN 1.0 ELSE 0.0 END))::numeric, 2) AS poor_experience_rate_pct
FROM gold.customer_intelligence ci
JOIN gold.customer_experience ce ON ci.customer_unique_id = ce.customer_unique_id
WHERE ci.customer_segment IN (
    'High-Value One-Time',
    'Recent One-Time',
    'Developing Repeat',
    'Low-Value Inactive'
)
GROUP BY ci.customer_segment
ORDER BY associated_revenue DESC;

-- -------------------------------------------------------------------
-- 8. Gold Layer Validation Checks
-- -------------------------------------------------------------------

-- Table Row Counts & Primary Key Integrity
SELECT 'gold.order_summary' AS table_name, COUNT(*) AS row_count, COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_keys FROM gold.order_summary
UNION ALL
SELECT 'gold.customer_360', COUNT(*), COUNT(*) - COUNT(DISTINCT customer_unique_id) FROM gold.customer_360
UNION ALL
SELECT 'gold.customer_experience', COUNT(*), COUNT(*) - COUNT(DISTINCT customer_unique_id) FROM gold.customer_experience
UNION ALL
SELECT 'gold.customer_intelligence', COUNT(*), COUNT(*) - COUNT(DISTINCT customer_unique_id) FROM gold.customer_intelligence;

-- KPI Baseline Validation
SELECT * FROM gold.executive_kpis;