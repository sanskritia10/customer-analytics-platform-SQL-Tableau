/*====================================================================
  03_DATA_QUALITY_ASSESSMENT.SQL
  Project: Customer Intelligence Platform
  Dataset: Olist Brazilian E-commerce Dataset
  Layer: Bronze

  Purpose:
    Execute 53 standard data quality assertions against raw bronze tables:
      1. Uniqueness & Primary Key integrity
      2. Completeness & Missing values
      3. Referential integrity & Orphan records
      4. Domain & Range constraints
      5. Temporal & Business sequence consistency
      6. Cross-table consistency
====================================================================*/

-- -------------------------------------------------------------------
-- Section 1: Customer Data Quality
-- -------------------------------------------------------------------

-- DQ-001: Uniqueness of customer_id
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_customer_id_rows
FROM bronze.olist_customers;

-- DQ-002: Customer unique identifier duplicates
SELECT
    customer_unique_id,
    COUNT(*) AS customer_id_count
FROM bronze.olist_customers
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
ORDER BY customer_id_count DESC;

-- DQ-003: Count of unique entities with multiple customer IDs
SELECT
    COUNT(*) AS customers_with_multiple_customer_ids
FROM (
    SELECT customer_unique_id
    FROM bronze.olist_customers
    GROUP BY customer_unique_id
    HAVING COUNT(DISTINCT customer_id) > 1
) x;

-- DQ-004: Missing customer identifiers
SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id,
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS missing_customer_unique_id
FROM bronze.olist_customers;

-- -------------------------------------------------------------------
-- Section 2: Order Data Quality
-- -------------------------------------------------------------------

-- DQ-005: Uniqueness of order_id
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_rows
FROM bronze.olist_orders;

-- DQ-006: Missing critical order identifiers
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id
FROM bronze.olist_orders;

-- DQ-007: Referential integrity — Orders to Customers
SELECT COUNT(*) AS orphan_orders
FROM bronze.olist_orders o
LEFT JOIN bronze.olist_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- -------------------------------------------------------------------
-- Section 3: Order Item Data Quality
-- -------------------------------------------------------------------

-- DQ-008: Composite key uniqueness (order_id, order_item_id)
SELECT
    order_id,
    order_item_id,
    COUNT(*) AS duplicate_count
FROM bronze.olist_order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- DQ-009: Missing critical order item identifiers
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS missing_product_id,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS missing_seller_id
FROM bronze.olist_order_items;

-- DQ-010: Referential integrity — Order Items to Orders
SELECT COUNT(*) AS orphan_order_items
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- DQ-011: Referential integrity — Order Items to Products
SELECT COUNT(*) AS orphan_product_references
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- DQ-012: Referential integrity — Order Items to Sellers
SELECT COUNT(*) AS orphan_seller_references
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- DQ-013: Negative or null item prices
SELECT COUNT(*) AS invalid_price_records
FROM bronze.olist_order_items
WHERE price < 0 OR price IS NULL;

-- DQ-014: Negative or null freight values
SELECT COUNT(*) AS invalid_freight_records
FROM bronze.olist_order_items
WHERE freight_value < 0 OR freight_value IS NULL;

-- -------------------------------------------------------------------
-- Section 4: Payment Data Quality
-- -------------------------------------------------------------------

-- DQ-015: Missing payment attributes
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE payment_sequential IS NULL) AS missing_payment_sequence,
    COUNT(*) FILTER (WHERE payment_type IS NULL) AS missing_payment_type
FROM bronze.olist_order_payments;

-- DQ-016: Referential integrity — Payments to Orders
SELECT COUNT(*) AS orphan_payments
FROM bronze.olist_order_payments p
LEFT JOIN bronze.olist_orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

-- DQ-017: Invalid payment values
SELECT
    COUNT(*) FILTER (WHERE payment_value < 0) AS negative_payment_values,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS missing_payment_values,
    COUNT(*) FILTER (WHERE payment_value = 0) AS zero_payment_values
FROM bronze.olist_order_payments;

-- DQ-018: Domain check — Payment Types
SELECT DISTINCT payment_type
FROM bronze.olist_order_payments
ORDER BY payment_type;

-- DQ-019: Invalid installments (< 1)
SELECT
    COUNT(*) AS invalid_installments
FROM bronze.olist_order_payments
WHERE payment_installments < 1 OR payment_installments IS NULL;

-- -------------------------------------------------------------------
-- Section 5: Review Data Quality
-- -------------------------------------------------------------------

-- DQ-020: Review score range validity (1-5)
SELECT COUNT(*) AS invalid_review_scores
FROM bronze.olist_order_reviews
WHERE review_score NOT BETWEEN 1 AND 5 OR review_score IS NULL;

-- DQ-021: Missing review identifiers
SELECT
    COUNT(*) FILTER (WHERE review_id IS NULL) AS missing_review_id,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id
FROM bronze.olist_order_reviews;

-- DQ-022: Referential integrity — Reviews to Orders
SELECT COUNT(*) AS orphan_reviews
FROM bronze.olist_order_reviews r
LEFT JOIN bronze.olist_orders o ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

-- DQ-023: Duplicate review IDs across records
SELECT
    review_id,
    COUNT(*) AS duplicate_count
FROM bronze.olist_order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1;

-- -------------------------------------------------------------------
-- Section 6: Timestamp & Temporal Integrity
-- -------------------------------------------------------------------

-- DQ-024: Temporal anomaly — Approved before purchase
SELECT COUNT(*) AS invalid_approval_timestamps
FROM bronze.olist_orders
WHERE order_approved_at < order_purchase_timestamp;

-- DQ-025: Temporal anomaly — Carrier dispatch before approval
SELECT COUNT(*) AS invalid_carrier_timestamps
FROM bronze.olist_orders
WHERE order_delivered_carrier_date < order_approved_at;

-- DQ-026: Temporal anomaly — Customer delivery before carrier dispatch
SELECT COUNT(*) AS invalid_delivery_sequence
FROM bronze.olist_orders
WHERE order_delivered_customer_date < order_delivered_carrier_date;

-- DQ-027: Temporal anomaly — Estimated delivery before purchase
SELECT COUNT(*) AS invalid_estimated_delivery
FROM bronze.olist_orders
WHERE order_estimated_delivery_date < order_purchase_timestamp::date;

-- DQ-028: Temporal anomaly — Customer delivery before purchase
SELECT COUNT(*) AS delivery_before_purchase
FROM bronze.olist_orders
WHERE order_delivered_customer_date < order_purchase_timestamp;

-- -------------------------------------------------------------------
-- Section 7: Order Status Business Rule Integrity
-- -------------------------------------------------------------------

-- DQ-029: Delivered orders missing customer delivery date
SELECT COUNT(*) AS delivered_without_delivery_date
FROM bronze.olist_orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

-- DQ-030: Delivered orders missing carrier date
SELECT COUNT(*) AS delivered_without_carrier_date
FROM bronze.olist_orders
WHERE order_status = 'delivered' AND order_delivered_carrier_date IS NULL;

-- DQ-031: Canceled orders with customer delivery date
SELECT COUNT(*) AS canceled_with_delivery_date
FROM bronze.olist_orders
WHERE order_status = 'canceled' AND order_delivered_customer_date IS NOT NULL;

-- DQ-032: Unavailable orders with customer delivery date
SELECT COUNT(*) AS unavailable_with_delivery_date
FROM bronze.olist_orders
WHERE order_status = 'unavailable' AND order_delivered_customer_date IS NOT NULL;

-- DQ-033: Domain check — Order status
SELECT DISTINCT order_status FROM bronze.olist_orders ORDER BY order_status;

-- -------------------------------------------------------------------
-- Section 8: Product Data Quality
-- -------------------------------------------------------------------

-- DQ-034: Uniqueness of product_id
SELECT
    COUNT(*) AS total_products,
    COUNT(DISTINCT product_id) AS distinct_product_ids,
    COUNT(*) - COUNT(DISTINCT product_id) AS duplicate_product_rows
FROM bronze.olist_products;

-- DQ-035: Missing product_id
SELECT COUNT(*) FILTER (WHERE product_id IS NULL) AS missing_product_id
FROM bronze.olist_products;

-- DQ-036: Invalid product weights (<= 0 or NULL)
SELECT
    COUNT(*) FILTER (WHERE product_weight_g < 0) AS negative_weight,
    COUNT(*) FILTER (WHERE product_weight_g = 0) AS zero_weight,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS missing_weight
FROM bronze.olist_products;

-- DQ-037: Invalid physical dimensions (<= 0)
SELECT
    COUNT(*) FILTER (WHERE product_length_cm <= 0) AS invalid_length,
    COUNT(*) FILTER (WHERE product_height_cm <= 0) AS invalid_height,
    COUNT(*) FILTER (WHERE product_width_cm <= 0) AS invalid_width
FROM bronze.olist_products;

-- DQ-038: Missing product categories
SELECT COUNT(*) AS missing_category
FROM bronze.olist_products
WHERE product_category_name IS NULL;

-- -------------------------------------------------------------------
-- Section 9: Seller Data Quality
-- -------------------------------------------------------------------

-- DQ-039: Uniqueness of seller_id
SELECT
    COUNT(*) AS total_sellers,
    COUNT(DISTINCT seller_id) AS distinct_sellers,
    COUNT(*) - COUNT(DISTINCT seller_id) AS duplicate_seller_rows
FROM bronze.olist_sellers;

-- DQ-040: Missing seller_id
SELECT COUNT(*) FILTER (WHERE seller_id IS NULL) AS missing_seller_id
FROM bronze.olist_sellers;

-- DQ-041: Missing seller location details
SELECT
    COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL) AS missing_zip,
    COUNT(*) FILTER (WHERE seller_city IS NULL) AS missing_city,
    COUNT(*) FILTER (WHERE seller_state IS NULL) AS missing_state
FROM bronze.olist_sellers;

-- -------------------------------------------------------------------
-- Section 10: Geolocation Data Quality
-- -------------------------------------------------------------------

-- DQ-042: Missing geolocation coordinates and fields
SELECT
    COUNT(*) FILTER (WHERE geolocation_zip_code_prefix IS NULL) AS missing_zip,
    COUNT(*) FILTER (WHERE geolocation_lat IS NULL) AS missing_latitude,
    COUNT(*) FILTER (WHERE geolocation_lng IS NULL) AS missing_longitude,
    COUNT(*) FILTER (WHERE geolocation_city IS NULL) AS missing_city,
    COUNT(*) FILTER (WHERE geolocation_state IS NULL) AS missing_state
FROM bronze.olist_geolocation;

-- DQ-043: Latitude boundaries (-90 to +90)
SELECT COUNT(*) AS invalid_latitude
FROM bronze.olist_geolocation
WHERE geolocation_lat NOT BETWEEN -90 AND 90;

-- DQ-044: Longitude boundaries (-180 to +180)
SELECT COUNT(*) AS invalid_longitude
FROM bronze.olist_geolocation
WHERE geolocation_lng NOT BETWEEN -180 AND 180;

-- DQ-045: Geographic multi-mapping (ZIP mapped to >1 state)
SELECT
    geolocation_zip_code_prefix,
    COUNT(DISTINCT geolocation_state) AS state_count
FROM bronze.olist_geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT geolocation_state) > 1
ORDER BY state_count DESC;

-- -------------------------------------------------------------------
-- Section 11: Category Translation Quality
-- -------------------------------------------------------------------

-- DQ-046: Duplicate translations
SELECT
    product_category_name,
    COUNT(*) AS occurrences
FROM bronze.product_category_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1;

-- DQ-047: Missing Portuguese or English translations
SELECT
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS missing_portuguese_category,
    COUNT(*) FILTER (WHERE product_category_name_english IS NULL) AS missing_english_category
FROM bronze.product_category_translation;

-- DQ-048: Missing category mappings in translation table
SELECT COUNT(*) AS untranslated_product_categories
FROM bronze.olist_products p
LEFT JOIN bronze.product_category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL;

-- -------------------------------------------------------------------
-- Section 12: Cross-Table Consistency & Deep Dives
-- -------------------------------------------------------------------

-- DQ-049: Orders without line items
SELECT COUNT(*) AS orders_without_items
FROM bronze.olist_orders o
LEFT JOIN (SELECT DISTINCT order_id FROM bronze.olist_order_items) oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;

-- DQ-050: Orders without payments
SELECT COUNT(*) AS orders_without_payment
FROM bronze.olist_orders o
LEFT JOIN (SELECT DISTINCT order_id FROM bronze.olist_order_payments) p ON o.order_id = p.order_id
WHERE p.order_id IS NULL;

-- DQ-051: Orders without reviews
SELECT COUNT(*) AS orders_without_review
FROM bronze.olist_orders o
LEFT JOIN (SELECT DISTINCT order_id FROM bronze.olist_order_reviews) r ON o.order_id = r.order_id
WHERE r.order_id IS NULL;

-- DQ-052: Order item sellers missing from seller dimension
SELECT COUNT(DISTINCT oi.seller_id) AS missing_sellers
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- DQ-053: Order item products missing from product dimension
SELECT COUNT(DISTINCT oi.product_id) AS missing_products
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Anomaly Deep Dive: Investigation of Carrier Dispatch vs Approval Timestamps
SELECT
    order_status,
    COUNT(*) AS affected_orders
FROM bronze.olist_orders
WHERE order_delivered_carrier_date < order_approved_at
GROUP BY order_status
ORDER BY affected_orders DESC;

-- Anomaly Deep Dive: Orders Without Items by Order Status
SELECT
    o.order_status,
    COUNT(*) AS orders_without_items
FROM bronze.olist_orders o
LEFT JOIN (SELECT DISTINCT order_id FROM bronze.olist_order_items) oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;