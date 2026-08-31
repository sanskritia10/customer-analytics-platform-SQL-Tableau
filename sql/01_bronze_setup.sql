/*====================================================================
  01_BRONZE_SETUP.SQL
  Project: Customer Intelligence Platform
  Dataset: Olist Brazilian E-commerce Dataset
  Layer: Bronze

  Purpose:
    - Initialize schema structure (Bronze, Silver, Gold).
    - Create raw ingestion tables without constraints or casting.
    - Ingest CSV source files and record ingestion audit metrics.
====================================================================*/

-- -------------------------------------------------------------------
-- 1. Schema Initialization
-- -------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

-- -------------------------------------------------------------------
-- 2. Drop Existing Bronze Tables (Idempotency)
-- -------------------------------------------------------------------
DROP TABLE IF EXISTS bronze.olist_customers CASCADE;
DROP TABLE IF EXISTS bronze.olist_orders CASCADE;
DROP TABLE IF EXISTS bronze.olist_order_items CASCADE;
DROP TABLE IF EXISTS bronze.olist_order_payments CASCADE;
DROP TABLE IF EXISTS bronze.olist_order_reviews CASCADE;
DROP TABLE IF EXISTS bronze.olist_products CASCADE;
DROP TABLE IF EXISTS bronze.olist_sellers CASCADE;
DROP TABLE IF EXISTS bronze.olist_geolocation CASCADE;
DROP TABLE IF EXISTS bronze.product_category_translation CASCADE;
DROP TABLE IF EXISTS bronze.load_audit CASCADE;

-- -------------------------------------------------------------------
-- 3. DDL: Create Bronze Raw Tables
-- -------------------------------------------------------------------
CREATE TABLE bronze.olist_customers (
    customer_id                 VARCHAR(32),
    customer_unique_id          VARCHAR(32),
    customer_zip_code_prefix    CHAR(5),
    customer_city               VARCHAR(100),
    customer_state              CHAR(2)
);

CREATE TABLE bronze.olist_orders (
    order_id                         VARCHAR(32),
    customer_id                      VARCHAR(32),
    order_status                    VARCHAR(20),
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   DATE
);

CREATE TABLE bronze.olist_order_items (
    order_id                VARCHAR(32),
    order_item_id           SMALLINT,
    product_id              VARCHAR(32),
    seller_id               VARCHAR(32),
    shipping_limit_date     TIMESTAMP,
    price                   NUMERIC(10,2),
    freight_value           NUMERIC(10,2)
);

CREATE TABLE bronze.olist_order_payments (
    order_id                 VARCHAR(32),
    payment_sequential       SMALLINT,
    payment_type             VARCHAR(30),
    payment_installments     SMALLINT,
    payment_value            NUMERIC(10,2)
);

CREATE TABLE bronze.olist_order_reviews (
    review_id                   VARCHAR(32),
    order_id                    VARCHAR(32),
    review_score                SMALLINT,
    review_comment_title        TEXT,
    review_comment_message      TEXT,
    review_creation_date        DATE,
    review_answer_timestamp     TIMESTAMP
);

CREATE TABLE bronze.olist_products (
    product_id                     VARCHAR(32),
    product_category_name          VARCHAR(100),
    product_name_length            SMALLINT,
    product_description_length     INTEGER,
    product_photos_qty             SMALLINT,
    product_weight_g               INTEGER,
    product_length_cm              SMALLINT,
    product_height_cm              SMALLINT,
    product_width_cm               SMALLINT
);

CREATE TABLE bronze.olist_sellers (
    seller_id                   VARCHAR(32),
    seller_zip_code_prefix      CHAR(5),
    seller_city                 VARCHAR(100),
    seller_state              CHAR(2)
);

CREATE TABLE bronze.olist_geolocation (
    geolocation_zip_code_prefix CHAR(5),
    geolocation_lat             NUMERIC(9,6),
    geolocation_lng             NUMERIC(9,6),
    geolocation_city            VARCHAR(100),
    geolocation_state           CHAR(2)
);

CREATE TABLE bronze.product_category_translation (
    product_category_name              VARCHAR(100),
    product_category_name_english      VARCHAR(100)
);

CREATE TABLE bronze.load_audit (
    table_name      VARCHAR(100),
    load_timestamp  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    row_count       INTEGER,
    status          VARCHAR(20)
);

-- -------------------------------------------------------------------
-- 4. Data Ingestion & Audit Logging
-- NOTE: Update local file paths if running in a different environment.
-- -------------------------------------------------------------------
COPY bronze.olist_customers
FROM 'data/olist_customers_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_customers', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_customers), 'SUCCESS');

COPY bronze.olist_orders
FROM 'data/olist_orders_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_orders', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_orders), 'SUCCESS');

COPY bronze.olist_order_items
FROM 'data/olist_order_items_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_order_items', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_order_items), 'SUCCESS');

COPY bronze.olist_order_payments
FROM 'data/olist_order_payments_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_order_payments', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_order_payments), 'SUCCESS');

COPY bronze.olist_order_reviews
FROM 'data/olist_order_reviews_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_order_reviews', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_order_reviews), 'SUCCESS');

COPY bronze.olist_products
FROM 'data/olist_products_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_products', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_products), 'SUCCESS');

COPY bronze.olist_sellers
FROM 'data/olist_sellers_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_sellers', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_sellers), 'SUCCESS');

COPY bronze.olist_geolocation
FROM 'data/olist_geolocation_dataset.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('olist_geolocation', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.olist_geolocation), 'SUCCESS');

COPY bronze.product_category_translation
FROM 'data/product_category_name_translation.csv'
DELIMITER ',' CSV HEADER;

INSERT INTO bronze.load_audit (table_name, load_timestamp, row_count, status)
VALUES ('product_category_translation', CURRENT_TIMESTAMP, (SELECT COUNT(*) FROM bronze.product_category_translation), 'SUCCESS');

-- -------------------------------------------------------------------
-- 5. Ingestion Verification
-- -------------------------------------------------------------------
SELECT * FROM bronze.load_audit ORDER BY load_timestamp DESC;