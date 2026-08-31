/*====================================================================
  06_SILVER_LAYER.SQL

  Project: Customer Intelligence Platform
  Dataset: Olist Brazilian E-commerce Dataset

  Purpose:
    Transform validated Bronze data into standardized Silver tables.

  Bronze = source/raw representation
  Silver = cleaned, standardized, validated representation

  IMPORTANT:
    Bronze tables are NOT modified.
====================================================================*/


/********************************************************************
  0. CREATE SILVER SCHEMA
********************************************************************/

CREATE SCHEMA IF NOT EXISTS silver;


/********************************************************************
  1. CUSTOMERS
  Grain: one row per customer_id
********************************************************************/

DROP TABLE IF EXISTS silver.customers;

CREATE TABLE silver.customers AS
SELECT
    customer_id,
    customer_unique_id,

    LPAD(
        CAST(customer_zip_code_prefix AS TEXT),
        5,
        '0'
    ) AS customer_zip_code_prefix,

    TRIM(LOWER(customer_city)) AS customer_city,
    UPPER(TRIM(customer_state)) AS customer_state

FROM bronze.olist_customers;


/********************************************************************
  2. ORDERS
  Grain: one row per order_id
********************************************************************/

DROP TABLE IF EXISTS silver.orders;

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

    /*
      Flag timestamp anomaly rather than modifying source values.
    */
    CASE
        WHEN order_delivered_carrier_date IS NOT NULL
         AND order_approved_at IS NOT NULL
         AND order_delivered_carrier_date < order_approved_at
        THEN TRUE
        ELSE FALSE
    END AS approval_carrier_timestamp_anomaly,

    /*
      Flag delivery sequence anomaly.
    */
    CASE
        WHEN order_delivered_customer_date IS NOT NULL
         AND order_delivered_carrier_date IS NOT NULL
         AND order_delivered_customer_date
             < order_delivered_carrier_date
        THEN TRUE
        ELSE FALSE
    END AS delivery_sequence_anomaly,

    /*
      Validated delivery duration.
      Only calculated when timestamps are logically ordered.
    */
    CASE
        WHEN order_delivered_customer_date IS NOT NULL
         AND order_purchase_timestamp IS NOT NULL
         AND order_delivered_customer_date >= order_purchase_timestamp
        THEN
            EXTRACT(
                EPOCH FROM (
                    order_delivered_customer_date
                    - order_purchase_timestamp
                )
            ) / 86400.0
        ELSE NULL
    END AS delivery_days,

    /*
      Estimated-vs-actual delivery performance.
    */
    CASE
        WHEN order_delivered_customer_date IS NOT NULL
         AND order_estimated_delivery_date IS NOT NULL
        THEN
            order_delivered_customer_date::DATE
            - order_estimated_delivery_date
        ELSE NULL
    END AS delivery_vs_estimate_days

FROM bronze.olist_orders;


/********************************************************************
  3. ORDER ITEMS
  Grain: one row per order_id + order_item_id
********************************************************************/

DROP TABLE IF EXISTS silver.order_items;

CREATE TABLE silver.order_items AS
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,

    shipping_limit_date,

    CAST(price AS NUMERIC(12,2)) AS price,
    CAST(freight_value AS NUMERIC(12,2)) AS freight_value,

    CAST(price + freight_value AS NUMERIC(12,2))
        AS item_total_value

FROM bronze.olist_order_items;


/********************************************************************
  4. PAYMENTS
  Grain: one row per payment record
********************************************************************/

DROP TABLE IF EXISTS silver.payments;

CREATE TABLE silver.payments AS
SELECT
    order_id,
    payment_sequential,
    LOWER(TRIM(payment_type)) AS payment_type,
    payment_installments,
    CAST(payment_value AS NUMERIC(14,2)) AS payment_value,

    /*
      Flag the two anomalous zero-installment records.
    */
    CASE
        WHEN payment_installments < 1
        THEN TRUE
        ELSE FALSE
    END AS invalid_installment_flag

FROM bronze.olist_order_payments;


/********************************************************************
  5. REVIEWS
  Grain: one row per review_id + order_id
********************************************************************/

DROP TABLE IF EXISTS silver.reviews;

CREATE TABLE silver.reviews AS
SELECT
    review_id,
    order_id,

    review_score,

    /*
      Preserve text; do not impute missing comments.
    */
    NULLIF(TRIM(review_comment_title), '') AS review_comment_title,
    NULLIF(TRIM(review_comment_message), '') AS review_comment_message,

    review_creation_date,
    review_answer_timestamp

FROM bronze.olist_order_reviews;


/********************************************************************
  6. PRODUCTS
  Grain: one row per product_id
********************************************************************/

DROP TABLE IF EXISTS silver.products;

CREATE TABLE silver.products AS
SELECT
    p.product_id,

    /*
      Standardized category.
      Missing categories are retained as Unknown.
    */
    COALESCE(
        NULLIF(TRIM(p.product_category_name), ''),
        'unknown'
    ) AS product_category_name,

    COALESCE(
        NULLIF(
            TRIM(t.product_category_name_english),
            ''
        ),
        'unknown'
    ) AS product_category_name_english,

    p.product_name_length,
    p.product_description_length,
    p.product_photos_qty,

    /*
      Preserve physical attributes.
      Zero weights are flagged rather than silently deleted.
    */
    p.product_weight_g,

    CASE
        WHEN p.product_weight_g = 0
        THEN TRUE
        ELSE FALSE
    END AS zero_weight_flag,

    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm

FROM bronze.olist_products p

LEFT JOIN bronze.product_category_translation t
    ON p.product_category_name = t.product_category_name;


/********************************************************************
  7. SELLERS
  Grain: one row per seller_id
********************************************************************/

DROP TABLE IF EXISTS silver.sellers;

CREATE TABLE silver.sellers AS
SELECT
    seller_id,

    LPAD(
        CAST(seller_zip_code_prefix AS TEXT),
        5,
        '0'
    ) AS seller_zip_code_prefix,

    TRIM(LOWER(seller_city)) AS seller_city,
    UPPER(TRIM(seller_state)) AS seller_state

FROM bronze.olist_sellers;


/********************************************************************
  8. GEOLOCATION
  Grain: one row per ZIP prefix

  The raw geolocation table contains multiple observations
  per ZIP prefix. We aggregate latitude/longitude and select
  the most frequently observed city/state combination.
********************************************************************/

DROP TABLE IF EXISTS silver.geolocation;

CREATE TABLE silver.geolocation AS

WITH geo_clean AS (

    SELECT
        LPAD(
            CAST(geolocation_zip_code_prefix AS TEXT),
            5,
            '0'
        ) AS zip_prefix,

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

    GROUP BY
        zip_prefix,
        city,
        state

),

ranked_locations AS (

    SELECT
        zip_prefix,
        city,
        state,
        observations,

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

    /*
      Flag ZIP prefixes where multiple states exist.
    */
    CASE
        WHEN COUNT(DISTINCT g.state) > 1
        THEN TRUE
        ELSE FALSE
    END AS geographic_ambiguity_flag

FROM coordinates c

JOIN ranked_locations r
    ON c.zip_prefix = r.zip_prefix
   AND r.rn = 1

JOIN geo_clean g
    ON c.zip_prefix = g.zip_prefix

GROUP BY
    c.zip_prefix,
    c.latitude,
    c.longitude,
    r.city,
    r.state;


/********************************************************************
  9. CATEGORY TRANSLATION
  Grain: one row per category
********************************************************************/

DROP TABLE IF EXISTS silver.category_translation;

CREATE TABLE silver.category_translation AS
SELECT
    TRIM(product_category_name) AS product_category_name,
    TRIM(product_category_name_english)
        AS product_category_name_english

FROM bronze.product_category_translation;


/********************************************************************
  10. BASIC SILVER INDEXES
********************************************************************/

CREATE INDEX IF NOT EXISTS idx_silver_customers_customer_id
    ON silver.customers(customer_id);

CREATE INDEX IF NOT EXISTS idx_silver_customers_unique_id
    ON silver.customers(customer_unique_id);

CREATE INDEX IF NOT EXISTS idx_silver_customers_zip
    ON silver.customers(customer_zip_code_prefix);

CREATE INDEX IF NOT EXISTS idx_silver_orders_order_id
    ON silver.orders(order_id);

CREATE INDEX IF NOT EXISTS idx_silver_orders_customer_id
    ON silver.orders(customer_id);

CREATE INDEX IF NOT EXISTS idx_silver_order_items_order_id
    ON silver.order_items(order_id);

CREATE INDEX IF NOT EXISTS idx_silver_order_items_product_id
    ON silver.order_items(product_id);

CREATE INDEX IF NOT EXISTS idx_silver_order_items_seller_id
    ON silver.order_items(seller_id);

CREATE INDEX IF NOT EXISTS idx_silver_payments_order_id
    ON silver.payments(order_id);

CREATE INDEX IF NOT EXISTS idx_silver_reviews_order_id
    ON silver.reviews(order_id);

CREATE INDEX IF NOT EXISTS idx_silver_products_product_id
    ON silver.products(product_id);

CREATE INDEX IF NOT EXISTS idx_silver_sellers_seller_id
    ON silver.sellers(seller_id);

CREATE INDEX IF NOT EXISTS idx_silver_geolocation_zip
    ON silver.geolocation(zip_prefix);


/********************************************************************
  11. SILVER TABLE SUMMARY
********************************************************************/

SELECT 'customers' AS table_name,
       COUNT(*) AS row_count
FROM silver.customers

UNION ALL

SELECT 'orders',
       COUNT(*)
FROM silver.orders

UNION ALL

SELECT 'order_items',
       COUNT(*)
FROM silver.order_items

UNION ALL

SELECT 'payments',
       COUNT(*)
FROM silver.payments

UNION ALL

SELECT 'reviews',
       COUNT(*)
FROM silver.reviews

UNION ALL

SELECT 'products',
       COUNT(*)
FROM silver.products

UNION ALL

SELECT 'sellers',
       COUNT(*)
FROM silver.sellers

UNION ALL

SELECT 'geolocation',
       COUNT(*)
FROM silver.geolocation

UNION ALL

SELECT 'category_translation',
       COUNT(*)
FROM silver.category_translation

ORDER BY table_name;