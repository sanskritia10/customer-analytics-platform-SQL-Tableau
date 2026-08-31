/*========================================================
  Bronze Layer Validation Checks
  Purpose:
  - Validate successful data ingestion
  - Check row counts
  - Inspect sample records
  - Identify missing primary identifiers
========================================================*/


/*========================================================
  1. Customers
========================================================*/

SELECT COUNT(*) AS customer_count
FROM bronze.olist_customers;

SELECT *
FROM bronze.olist_customers
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id
FROM bronze.olist_customers;

SELECT
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS missing_customer_id
FROM bronze.olist_customers;


/*========================================================
  2. Orders
========================================================*/

SELECT COUNT(*) AS order_count
FROM bronze.olist_orders;

SELECT *
FROM bronze.olist_orders
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id
FROM bronze.olist_orders;


/*========================================================
  3. Order Items
========================================================*/

SELECT COUNT(*) AS order_item_count
FROM bronze.olist_order_items;

SELECT *
FROM bronze.olist_order_items
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id
FROM bronze.olist_order_items;


/*========================================================
  4. Order Payments
========================================================*/

SELECT COUNT(*) AS payment_count
FROM bronze.olist_order_payments;

SELECT *
FROM bronze.olist_order_payments
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id
FROM bronze.olist_order_payments;


/*========================================================
  5. Order Reviews
========================================================*/

SELECT COUNT(*) AS review_count
FROM bronze.olist_order_reviews;

SELECT *
FROM bronze.olist_order_reviews
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE review_id IS NULL) AS missing_review_id
FROM bronze.olist_order_reviews;


/*========================================================
  6. Products
========================================================*/

SELECT COUNT(*) AS product_count
FROM bronze.olist_products;

SELECT *
FROM bronze.olist_products
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE product_id IS NULL) AS missing_product_id
FROM bronze.olist_products;


/*========================================================
  7. Sellers
========================================================*/

SELECT COUNT(*) AS seller_count
FROM bronze.olist_sellers;

SELECT *
FROM bronze.olist_sellers
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS missing_seller_id
FROM bronze.olist_sellers;


/*========================================================
  8. Geolocation
========================================================*/

SELECT COUNT(*) AS geolocation_count
FROM bronze.olist_geolocation;

SELECT *
FROM bronze.olist_geolocation
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE geolocation_zip_code_prefix IS NULL) AS missing_zip_code
FROM bronze.olist_geolocation;


/*========================================================
  9. Product Category Translation
========================================================*/

SELECT COUNT(*) AS category_translation_count
FROM bronze.product_category_translation;

SELECT *
FROM bronze.product_category_translation
LIMIT 10;

SELECT
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS missing_category_name
FROM bronze.product_category_translation;

