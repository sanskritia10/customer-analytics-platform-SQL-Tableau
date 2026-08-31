/*========================================================
  Project: Customer Analytics Platform
  Layer: Bronze
  Purpose: Raw ingestion tables for Olist e-commerce data

  Design Principles:
  - Preserve source data structure
  - Minimal transformations
  - No business logic
  - No constraints in raw layer
========================================================*/


/*========================================================
  Drop existing tables (for reruns)
========================================================*/

DROP TABLE IF EXISTS bronze.olist_customers;
DROP TABLE IF EXISTS bronze.olist_orders;
DROP TABLE IF EXISTS bronze.olist_order_items;
DROP TABLE IF EXISTS bronze.olist_order_payments;
DROP TABLE IF EXISTS bronze.olist_order_reviews;
DROP TABLE IF EXISTS bronze.olist_products;
DROP TABLE IF EXISTS bronze.olist_sellers;
DROP TABLE IF EXISTS bronze.olist_geolocation;
DROP TABLE IF EXISTS bronze.product_category_translation;
DROP TABLE IF EXISTS bronze.load_audit;


/*========================================================
  1. Customers Table
========================================================*/

CREATE TABLE bronze.olist_customers
(
    customer_id                 VARCHAR(32),
    customer_unique_id          VARCHAR(32),
    customer_zip_code_prefix    CHAR(5),
    customer_city               VARCHAR(100),
    customer_state              CHAR(2)
);


/*========================================================
  2. Orders Table
========================================================*/

CREATE TABLE bronze.olist_orders
(
    order_id                         VARCHAR(32),
    customer_id                      VARCHAR(32),
    order_status                    VARCHAR(20),
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   DATE
);


/*========================================================
  3. Order Items Table
========================================================*/

CREATE TABLE bronze.olist_order_items
(
    order_id                VARCHAR(32),
    order_item_id           SMALLINT,
    product_id              VARCHAR(32),
    seller_id               VARCHAR(32),
    shipping_limit_date     TIMESTAMP,
    price                   NUMERIC(10,2),
    freight_value           NUMERIC(10,2)
);


/*========================================================
  4. Order Payments Table
========================================================*/

CREATE TABLE bronze.olist_order_payments
(
    order_id                 VARCHAR(32),
    payment_sequential       SMALLINT,
    payment_type             VARCHAR(30),
    payment_installments     SMALLINT,
    payment_value            NUMERIC(10,2)
);


/*========================================================
  5. Order Reviews Table
========================================================*/

CREATE TABLE bronze.olist_order_reviews
(
    review_id                   VARCHAR(32),
    order_id                    VARCHAR(32),
    review_score                SMALLINT,
    review_comment_title        TEXT,
    review_comment_message      TEXT,
    review_creation_date        DATE,
    review_answer_timestamp     TIMESTAMP
);


/*========================================================
  6. Products Table
========================================================*/

CREATE TABLE bronze.olist_products
(
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


/*========================================================
  7. Sellers Table
========================================================*/

CREATE TABLE bronze.olist_sellers
(
    seller_id                   VARCHAR(32),
    seller_zip_code_prefix      CHAR(5),
    seller_city                 VARCHAR(100),
    seller_state                CHAR(2)
);


/*========================================================
  8. Geolocation Table
========================================================*/

CREATE TABLE bronze.olist_geolocation
(
    geolocation_zip_code_prefix CHAR(5),
    geolocation_lat             NUMERIC(9,6),
    geolocation_lng             NUMERIC(9,6),
    geolocation_city            VARCHAR(100),
    geolocation_state           CHAR(2)
);


/*========================================================
  9. Product Category Translation Table
========================================================*/

CREATE TABLE bronze.product_category_translation
(
    product_category_name              VARCHAR(100),
    product_category_name_english      VARCHAR(100)
);

/*========================================================
  10. Load audit Table
========================================================*/

CREATE TABLE bronze.load_audit
(
    table_name VARCHAR(100),
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    row_count INTEGER,
    status VARCHAR(20)
);

/*========================================================
  Validation Query
========================================================*/

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'bronze'
ORDER BY table_name;


/*========================================================
  Load Data
========================================================*/

COPY bronze.olist_customers
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_customers_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_customers',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_customers),
'SUCCESS'
);

COPY bronze.olist_orders
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_orders_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_orders',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_orders),
'SUCCESS'
);

COPY bronze.olist_order_items
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_order_items_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_order_items',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_order_items),
'SUCCESS'
);

COPY bronze.olist_order_payments
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_order_payments_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_order_payments',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_order_payments),
'SUCCESS'
);

COPY bronze.olist_order_reviews
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_order_reviews_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_order_reviews',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_order_reviews),
'SUCCESS'
);

COPY bronze.olist_products
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_products_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_products',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_products),
'SUCCESS'
);

COPY bronze.olist_sellers
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_sellers_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_sellers',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_sellers),
'SUCCESS'
);

COPY bronze.olist_geolocation
FROM 'D:/GIPE/Z/Project 2/Olist dataset/olist_geolocation_dataset.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'olist_geolocation',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.olist_geolocation),
'SUCCESS'
);

COPY bronze.product_category_translation
FROM 'D:/GIPE/Z/Project 2/Olist dataset/product_category_name_translation.csv'
DELIMITER ','
CSV HEADER;

INSERT INTO bronze.load_audit
VALUES
(
'product_category_translation',
CURRENT_TIMESTAMP,
(SELECT COUNT(*) FROM bronze.product_category_translation),
'SUCCESS'
);

SELECT * FROM bronze.load_audit;