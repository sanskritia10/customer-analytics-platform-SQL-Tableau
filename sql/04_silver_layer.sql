/*====================================================================
  04_SILVER_LAYER.SQL
  Project: Customer Intelligence Platform
  Dataset: Olist Brazilian E-commerce Dataset
  Layer: Silver

  Purpose:
    - Clean, standardize, and transform Bronze data into curated Silver tables.
    - Standardize text, pad ZIP codes, calculate derived metrics, and flag anomalies.
    - Create performance indexes.
    - Run end-to-end reconciliation tests against Bronze.
====================================================================*/

-- -------------------------------------------------------------------
-- 1. Silver Schema Setup
-- -------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS silver;

-- -------------------------------------------------------------------
-- 2. Silver Tables DDL / Transformation
-- -------------------------------------------------------------------

-- Customers: Pad ZIP codes, lowercase/trim city & state
DROP TABLE IF EXISTS silver.customers CASCADE;
CREATE TABLE silver.customers AS
SELECT
    customer_id,
    customer_unique_id,
    LPAD(CAST(customer_zip_code_prefix AS TEXT), 5, '0') AS customer_zip_code_prefix,
    TRIM(LOWER(customer_city)) AS customer_city,
    UPPER(TRIM(customer_state)) AS customer_state
FROM bronze.olist_customers;

-- Orders: Standardize text, flag timestamp sequence anomalies, derive metrics
DROP TABLE IF EXISTS silver.orders CASCADE;
CREATE TABLE silver.orders AS
SELECT
    order_id,
    customer_id,
    LOWER(TRIM(order_status)) AS order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,

    -- Data Quality Flags
    CASE
        WHEN order_delivered_carrier_date IS NOT NULL
         AND order_approved_at IS NOT NULL
         AND order_delivered_carrier_date < order_approved_at
        THEN TRUE
        ELSE FALSE
    END AS approval_carrier_timestamp_anomaly,

    CASE
        WHEN order_delivered_customer_date IS NOT NULL
         AND order_delivered_carrier_date IS NOT NULL
         AND order_delivered_customer_date < order_delivered_carrier_date
        THEN TRUE
        ELSE FALSE
    END AS delivery_sequence_anomaly,

    -- Business Metrics
    CASE
        WHEN order_delivered_customer_date IS NOT NULL
         AND order_purchase_timestamp IS NOT NULL
         AND order_delivered_customer_date >= order_purchase_timestamp
        THEN EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400.0
        ELSE NULL
    END AS delivery_days,

    CASE
        WHEN order_delivered_customer_date IS NOT NULL
         AND order_estimated_delivery_date IS NOT NULL
        THEN order_delivered_customer_date::DATE - order_estimated_delivery_date
        ELSE NULL
    END AS delivery_vs_estimate_days
FROM bronze.olist_orders;

-- Order Items: Cast decimals and compute total item amount
DROP TABLE IF EXISTS silver.order_items CASCADE;
CREATE TABLE silver.order_items AS
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    CAST(price AS NUMERIC(12,2)) AS price,
    CAST(freight_value AS NUMERIC(12,2)) AS freight_value,
    CAST(price + freight_value AS NUMERIC(12,2)) AS item_total_value
FROM bronze.olist_order_items;

-- Payments: Normalize payment type and flag invalid installment counts
DROP TABLE IF EXISTS silver.payments CASCADE;
CREATE TABLE silver.payments AS
SELECT
    order_id,
    payment_sequential,
    LOWER(TRIM(payment_type)) AS payment_type,
    payment_installments,
    CAST(payment_value AS NUMERIC(14,2)) AS payment_value,
    CASE
        WHEN payment_installments < 1 THEN TRUE
        ELSE FALSE
    END AS invalid_installment_flag
FROM bronze.olist_order_payments;

-- Reviews: Convert empty strings to NULLs
DROP TABLE IF EXISTS silver.reviews CASCADE;
CREATE TABLE silver.reviews AS
SELECT
    review_id,
    order_id,
    review_score,
    NULLIF(TRIM(review_comment_title), '') AS review_comment_title,
    NULLIF(TRIM(review_comment_message), '') AS review_comment_message,
    review_creation_date,
    review_answer_timestamp
FROM bronze.olist_order_reviews;

-- Products: Join English translations and flag zero weights
DROP TABLE IF EXISTS silver.products CASCADE;
CREATE TABLE silver.products AS
SELECT
    p.product_id,
    COALESCE(NULLIF(TRIM(p.product_category_name), ''), 'unknown') AS product_category_name,
    COALESCE(NULLIF(TRIM(t.product_category_name_english), ''), 'unknown') AS product_category_name_english,
    p.product_name_length,
    p.product_description_length,
    p.product_photos_qty,
    p.product_weight_g,
    CASE
        WHEN p.product_weight_g = 0 THEN TRUE
        ELSE FALSE
    END AS zero_weight_flag,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM bronze.olist_products p
LEFT JOIN bronze.product_category_translation t
    ON p.product_category_name = t.product_category_name;

-- Sellers: Pad ZIP code and standardize strings
DROP TABLE IF EXISTS silver.sellers CASCADE;
CREATE TABLE silver.sellers AS
SELECT
    seller_id,
    LPAD(CAST(seller_zip_code_prefix AS TEXT), 5, '0') AS seller_zip_code_prefix,
    TRIM(LOWER(seller_city)) AS seller_city,
    UPPER(TRIM(seller_state)) AS seller_state
FROM bronze.olist_sellers;

-- Geolocation: Aggregate coordinate duplicates and select primary city/state
DROP TABLE IF EXISTS silver.geolocation CASCADE;
CREATE TABLE silver.geolocation AS
WITH geo_clean AS (
    SELECT
        LPAD(CAST(geolocation_zip_code_prefix AS TEXT), 5, '0') AS zip_prefix,
        geolocation_lat,
        geolocation_lng,
        TRIM(LOWER(geolocation_city)) AS city,
        UPPER(TRIM(geolocation_state)) AS state
    FROM bronze.olist_geolocation
),
city_state_frequency AS (
    SELECT
        zip_prefix,
        city,
        state,
        COUNT(*) AS observations
    FROM geo_clean
    GROUP BY zip_prefix, city, state
),
ranked_locations AS (
    SELECT
        zip_prefix,
        city,
        state,
        ROW_NUMBER() OVER (
            PARTITION BY zip_prefix
            ORDER BY observations DESC, city, state
        ) AS rn
    FROM city_state_frequency
),
coordinates AS (
    SELECT
        zip_prefix,
        AVG(geolocation_lat) AS latitude,
        AVG(geolocation_lng) AS longitude
    FROM geo_clean
    GROUP BY zip_prefix
)
SELECT
    c.zip_prefix,
    c.latitude,
    c.longitude,
    r.city,
    r.state,
    CASE
        WHEN COUNT(DISTINCT g.state) > 1 THEN TRUE
        ELSE FALSE
    END AS geographic_ambiguity_flag
FROM coordinates c
JOIN ranked_locations r
    ON c.zip_prefix = r.zip_prefix AND r.rn = 1
JOIN geo_clean g
    ON c.zip_prefix = g.zip_prefix
GROUP BY
    c.zip_prefix,
    c.latitude,
    c.longitude,
    r.city,
    r.state;

-- Category Translation: Standardized reference
DROP TABLE IF EXISTS silver.category_translation CASCADE;
CREATE TABLE silver.category_translation AS
SELECT
    TRIM(product_category_name) AS product_category_name,
    TRIM(product_category_name_english) AS product_category_name_english
FROM bronze.product_category_translation;

-- -------------------------------------------------------------------
-- 3. Performance Indexes
-- -------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_silver_customers_customer_id ON silver.customers(customer_id);
CREATE INDEX IF NOT EXISTS idx_silver_customers_unique_id ON silver.customers(customer_unique_id);
CREATE INDEX IF NOT EXISTS idx_silver_customers_zip ON silver.customers(customer_zip_code_prefix);
CREATE INDEX IF NOT EXISTS idx_silver_orders_order_id ON silver.orders(order_id);
CREATE INDEX IF NOT EXISTS idx_silver_orders_customer_id ON silver.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_silver_order_items_order_id ON silver.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_silver_order_items_product_id ON silver.order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_silver_order_items_seller_id ON silver.order_items(seller_id);
CREATE INDEX IF NOT EXISTS idx_silver_payments_order_id ON silver.payments(order_id);
CREATE INDEX IF NOT EXISTS idx_silver_reviews_order_id ON silver.reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_silver_products_product_id ON silver.products(product_id);
CREATE INDEX IF NOT EXISTS idx_silver_sellers_seller_id ON silver.sellers(seller_id);
CREATE INDEX IF NOT EXISTS idx_silver_geolocation_zip ON silver.geolocation(zip_prefix);

-- -------------------------------------------------------------------
-- 4. Silver Layer Post-Load Validation
-- -------------------------------------------------------------------

-- Row Count Reconciliation
SELECT
    'customers' AS table_name,
    (SELECT COUNT(*) FROM bronze.olist_customers) AS bronze_rows,
    (SELECT COUNT(*) FROM silver.customers) AS silver_rows,
    (SELECT COUNT(*) FROM silver.customers) - (SELECT COUNT(*) FROM bronze.olist_customers) AS difference
UNION ALL
SELECT
    'orders',
    (SELECT COUNT(*) FROM bronze.olist_orders),
    (SELECT COUNT(*) FROM silver.orders),
    (SELECT COUNT(*) FROM silver.orders) - (SELECT COUNT(*) FROM bronze.olist_orders)
UNION ALL
SELECT
    'order_items',
    (SELECT COUNT(*) FROM bronze.olist_order_items),
    (SELECT COUNT(*) FROM silver.order_items),
    (SELECT COUNT(*) FROM silver.order_items) - (SELECT COUNT(*) FROM bronze.olist_order_items)
UNION ALL
SELECT
    'payments',
    (SELECT COUNT(*) FROM bronze.olist_order_payments),
    (SELECT COUNT(*) FROM silver.payments),
    (SELECT COUNT(*) FROM silver.payments) - (SELECT COUNT(*) FROM bronze.olist_order_payments)
UNION ALL
SELECT
    'reviews',
    (SELECT COUNT(*) FROM bronze.olist_order_reviews),
    (SELECT COUNT(*) FROM silver.reviews),
    (SELECT COUNT(*) FROM silver.reviews) - (SELECT COUNT(*) FROM bronze.olist_order_reviews)
UNION ALL
SELECT
    'products',
    (SELECT COUNT(*) FROM bronze.olist_products),
    (SELECT COUNT(*) FROM silver.products),
    (SELECT COUNT(*) FROM silver.products) - (SELECT COUNT(*) FROM bronze.olist_products)
UNION ALL
SELECT
    'sellers',
    (SELECT COUNT(*) FROM bronze.olist_sellers),
    (SELECT COUNT(*) FROM silver.sellers),
    (SELECT COUNT(*) FROM silver.sellers) - (SELECT COUNT(*) FROM bronze.olist_sellers)
UNION ALL
SELECT
    'geolocation (deduplicated)',
    (SELECT COUNT(DISTINCT LPAD(CAST(geolocation_zip_code_prefix AS TEXT), 5, '0')) FROM bronze.olist_geolocation),
    (SELECT COUNT(*) FROM silver.geolocation),
    (SELECT COUNT(*) FROM silver.geolocation) - (SELECT COUNT(DISTINCT LPAD(CAST(geolocation_zip_code_prefix AS TEXT), 5, '0')) FROM bronze.olist_geolocation);

-- Key Uniqueness Checks
SELECT 'customers' AS table_name, COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_keys FROM silver.customers
UNION ALL
SELECT 'orders', COUNT(*) - COUNT(DISTINCT order_id) FROM silver.orders
UNION ALL
SELECT 'order_items', COUNT(*) - COUNT(DISTINCT (order_id, order_item_id)) FROM silver.order_items
UNION ALL
SELECT 'products', COUNT(*) - COUNT(DISTINCT product_id) FROM silver.products
UNION ALL
SELECT 'sellers', COUNT(*) - COUNT(DISTINCT seller_id) FROM silver.sellers
UNION ALL
SELECT 'reviews', COUNT(*) - COUNT(DISTINCT (review_id, order_id)) FROM silver.reviews;

-- Foreign Key Referential Integrity Checks
SELECT 'orphan_orders' AS check_name, COUNT(*) AS violations
FROM silver.orders o LEFT JOIN silver.customers c ON o.customer_id = c.customer_id WHERE c.customer_id IS NULL
UNION ALL
SELECT 'orphan_order_items_orders', COUNT(*)
FROM silver.order_items oi LEFT JOIN silver.orders o ON oi.order_id = o.order_id WHERE o.order_id IS NULL
UNION ALL
SELECT 'orphan_order_items_products', COUNT(*)
FROM silver.order_items oi LEFT JOIN silver.products p ON oi.product_id = p.product_id WHERE p.product_id IS NULL
UNION ALL
SELECT 'orphan_order_items_sellers', COUNT(*)
FROM silver.order_items oi LEFT JOIN silver.sellers s ON oi.seller_id = s.seller_id WHERE s.seller_id IS NULL
UNION ALL
SELECT 'orphan_payments_orders', COUNT(*)
FROM silver.payments p LEFT JOIN silver.orders o ON p.order_id = o.order_id WHERE o.order_id IS NULL
UNION ALL
SELECT 'orphan_reviews_orders', COUNT(*)
FROM silver.reviews r LEFT JOIN silver.orders o ON r.order_id = o.order_id WHERE o.order_id IS NULL;

-- Standardization & Metric Sanity Check
SELECT
    (SELECT COUNT(*) FROM silver.customers WHERE LENGTH(customer_zip_code_prefix) <> 5) AS invalid_cust_zip_lengths,
    (SELECT COUNT(*) FROM silver.sellers WHERE LENGTH(seller_zip_code_prefix) <> 5) AS invalid_seller_zip_lengths,
    (SELECT COUNT(*) FROM silver.orders WHERE delivery_days < 0) AS negative_delivery_days,
    (SELECT COUNT(*) FROM silver.payments WHERE invalid_installment_flag = TRUE) AS flagged_installments,
    (SELECT COUNT(*) FROM silver.products WHERE zero_weight_flag = TRUE) AS zero_weight_products;