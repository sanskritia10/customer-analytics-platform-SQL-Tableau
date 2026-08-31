/*====================================================================
  02_DATA_PROFILING.SQL
  Project: Customer Intelligence Platform
  Dataset: Olist Brazilian E-commerce Dataset
  Layer: Bronze

  Purpose:
    Perform Exploratory Data Analysis (EDA) on raw bronze tables to
    understand row counts, distributions, cardinatlity, and column-level nulls.
====================================================================*/

-- -------------------------------------------------------------------
-- 1. Table-Level Row Count Profiling
-- -------------------------------------------------------------------
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM bronze.olist_customers
UNION ALL
SELECT 'orders', COUNT(*) FROM bronze.olist_orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM bronze.olist_order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM bronze.olist_order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM bronze.olist_order_reviews
UNION ALL
SELECT 'products', COUNT(*) FROM bronze.olist_products
UNION ALL
SELECT 'sellers', COUNT(*) FROM bronze.olist_sellers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM bronze.olist_geolocation
UNION ALL
SELECT 'category_translation', COUNT(*) FROM bronze.product_category_translation
ORDER BY row_count DESC;

-- -------------------------------------------------------------------
-- 2. Domain & Distribution Profiling
-- -------------------------------------------------------------------

-- Customers: Cardinality and Geographic Spread
SELECT
    COUNT(*) AS total_rows,
    COUNT(customer_id) AS non_null_customer_id,
    COUNT(DISTINCT customer_id) AS distinct_customer_id,
    COUNT(DISTINCT customer_unique_id) AS distinct_customer_unique_id
FROM bronze.olist_customers;

SELECT 
    customer_state, 
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage_of_customers
FROM bronze.olist_customers
GROUP BY customer_state
ORDER BY customers DESC;

SELECT 
    customer_state, 
    COUNT(DISTINCT customer_city) AS distinct_cities
FROM bronze.olist_customers
GROUP BY customer_state
ORDER BY distinct_cities DESC;

-- Orders: Timeline and Status Breakdown
SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT customer_id) AS distinct_customers,
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM bronze.olist_orders;

SELECT
    EXTRACT(YEAR FROM order_purchase_timestamp) AS order_year,
    COUNT(*) AS orders
FROM bronze.olist_orders
GROUP BY order_year
ORDER BY order_year;

SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage_of_orders
FROM bronze.olist_orders
GROUP BY order_status
ORDER BY order_count DESC;

-- Order Items: Pricing & Freight Distribution
SELECT
    COUNT(*) AS total_items,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT product_id) AS distinct_products,
    COUNT(DISTINCT seller_id) AS distinct_sellers,
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    ROUND(AVG(price), 2) AS avg_price,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY price)::numeric, 2) AS median_price,
    MIN(freight_value) AS min_freight,
    MAX(freight_value) AS max_freight,
    ROUND(AVG(freight_value), 2) AS avg_freight,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY freight_value)::numeric, 2) AS median_freight
FROM bronze.olist_order_items;

-- Payments: Payment Methods & Value Spread
SELECT
    payment_type,
    COUNT(*) AS transactions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM bronze.olist_order_payments
GROUP BY payment_type
ORDER BY transactions DESC;

SELECT
    MIN(payment_value) AS min_payment,
    MAX(payment_value) AS max_payment,
    ROUND(AVG(payment_value), 2) AS avg_payment,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY payment_value)::numeric, 2) AS median_payment
FROM bronze.olist_order_payments;

-- Products: Categories & Weight Metrics
SELECT
    COUNT(*) AS total_products,
    COUNT(DISTINCT product_id) AS distinct_products,
    COUNT(DISTINCT product_category_name) AS categories,
    MIN(product_weight_g) AS min_weight,
    MAX(product_weight_g) AS max_weight,
    ROUND(AVG(product_weight_g), 2) AS avg_weight,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY product_weight_g)::numeric, 2) AS median_weight
FROM bronze.olist_products;

SELECT
    product_category_name,
    COUNT(*) AS product_count
FROM bronze.olist_products
GROUP BY product_category_name
ORDER BY product_count DESC
LIMIT 5;

-- Reviews: Score Breakdown & Comment Completeness
SELECT
    review_score,
    COUNT(*) AS review_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM bronze.olist_order_reviews
GROUP BY review_score
ORDER BY review_score;

SELECT
    COUNT(*) AS total_reviews,
    COUNT(review_comment_title) AS reviews_with_title,
    ROUND(100.0 * COUNT(review_comment_title) / COUNT(*), 2) AS perc_reviews_with_title,
    COUNT(review_comment_message) AS reviews_with_message,
    ROUND(100.0 * COUNT(review_comment_message) / COUNT(*), 2) AS perc_reviews_with_message
FROM bronze.olist_order_reviews;

-- Sellers & Geolocation
SELECT
    COUNT(*) AS total_sellers,
    COUNT(DISTINCT seller_id) AS distinct_sellers,
    COUNT(DISTINCT seller_state) AS states
FROM bronze.olist_sellers;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zip_prefixes,
    COUNT(DISTINCT geolocation_city) AS distinct_cities,
    COUNT(DISTINCT geolocation_state) AS distinct_states
FROM bronze.olist_geolocation;

-- -------------------------------------------------------------------
-- 3. Completeness Profiling: Missing Value Breakdown
-- -------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id,
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS missing_customer_unique_id,
    COUNT(*) FILTER (WHERE customer_zip_code_prefix IS NULL) AS missing_zip,
    COUNT(*) FILTER (WHERE customer_city IS NULL) AS missing_customer_city,
    COUNT(*) FILTER (WHERE customer_state IS NULL) AS missing_customer_state
FROM bronze.olist_customers;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id,
    COUNT(*) FILTER (WHERE order_status IS NULL) AS missing_order_status,
    COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL) AS missing_purchase_timestamp,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL) AS missing_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL) AS missing_carrier_date,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS missing_delivery_date,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL) AS missing_estimated_delivery_date
FROM bronze.olist_orders;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE order_item_id IS NULL) AS missing_order_item_id,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS missing_product_id,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS missing_seller_id,
    COUNT(*) FILTER (WHERE shipping_limit_date IS NULL) AS missing_shipping_limit_date,
    COUNT(*) FILTER (WHERE price IS NULL) AS missing_price,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS missing_freight_value
FROM bronze.olist_order_items;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE payment_sequential IS NULL) AS missing_payment_sequential,
    COUNT(*) FILTER (WHERE payment_type IS NULL) AS missing_payment_type,
    COUNT(*) FILTER (WHERE payment_installments IS NULL) AS missing_payment_installments,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS missing_payment_value
FROM bronze.olist_order_payments;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE review_id IS NULL) AS missing_review_id,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE review_score IS NULL) AS missing_review_score,
    COUNT(*) FILTER (WHERE review_comment_title IS NULL) AS missing_review_comment_title,
    COUNT(*) FILTER (WHERE review_comment_message IS NULL) AS missing_review_comment_message,
    COUNT(*) FILTER (WHERE review_creation_date IS NULL) AS missing_review_creation_date,
    COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL) AS missing_review_answer_timestamp
FROM bronze.olist_order_reviews;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS missing_product_id,
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS missing_product_category_name,
    COUNT(*) FILTER (WHERE product_name_length IS NULL) AS missing_product_name_length,
    COUNT(*) FILTER (WHERE product_description_length IS NULL) AS missing_product_description_length,
    COUNT(*) FILTER (WHERE product_photos_qty IS NULL) AS missing_product_photos_qty,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS missing_product_weight_g,
    COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS missing_product_length_cm,
    COUNT(*) FILTER (WHERE product_height_cm IS NULL) AS missing_product_height_cm,
    COUNT(*) FILTER (WHERE product_width_cm IS NULL) AS missing_product_width_cm
FROM bronze.olist_products;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS missing_seller_id,
    COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL) AS missing_seller_zip_code_prefix,
    COUNT(*) FILTER (WHERE seller_city IS NULL) AS missing_seller_city,
    COUNT(*) FILTER (WHERE seller_state IS NULL) AS missing_seller_state
FROM bronze.olist_sellers;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE geolocation_zip_code_prefix IS NULL) AS missing_zip,
    COUNT(*) FILTER (WHERE geolocation_lat IS NULL) AS missing_lat,
    COUNT(*) FILTER (WHERE geolocation_lng IS NULL) AS missing_lng,
    COUNT(*) FILTER (WHERE geolocation_city IS NULL) AS missing_city,
    COUNT(*) FILTER (WHERE geolocation_state IS NULL) AS missing_state
FROM bronze.olist_geolocation;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS missing_portuguese_name,
    COUNT(*) FILTER (WHERE product_category_name_english IS NULL) AS missing_english_name
FROM bronze.product_category_translation;