/*====================================================================
  05_DATA_QUALITY_ASSESSMENT.SQL

  Project: Customer Intelligence Platform
  Dataset: Olist Brazilian E-commerce Dataset
  Layer: Bronze

  Purpose:
  Validate:
    1. Uniqueness
    2. Completeness
    3. Referential integrity
    4. Domain validity
    5. Temporal consistency
    6. Business-rule consistency
    7. Geographic integrity

  IMPORTANT:
  This script ONLY READS from the Bronze layer.
  No data is modified at this stage.
====================================================================*/


/********************************************************************
  SECTION 1 — CUSTOMER DATA QUALITY
********************************************************************/


/* DQ-001: Are customer_id values unique? */

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_customer_id_rows
FROM bronze.olist_customers;


/* DQ-002: Are customer_unique_id values duplicated? */

SELECT
    customer_unique_id,
    COUNT(*) AS customer_id_count
FROM bronze.olist_customers
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
ORDER BY customer_id_count DESC;


/* DQ-003: How many customer_unique_ids are associated
           with multiple customer_ids? */

SELECT
    COUNT(*) AS customers_with_multiple_customer_ids
FROM (
    SELECT
        customer_unique_id
    FROM bronze.olist_customers
    GROUP BY customer_unique_id
    HAVING COUNT(DISTINCT customer_id) > 1
) x;


/* DQ-004: Missing customer identifiers */

SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL)
        AS missing_customer_id,

    COUNT(*) FILTER (WHERE customer_unique_id IS NULL)
        AS missing_customer_unique_id
FROM bronze.olist_customers;



/********************************************************************
  SECTION 2 — ORDER DATA QUALITY
********************************************************************/


/* DQ-005: Are order_id values unique? */

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_rows
FROM bronze.olist_orders;


/* DQ-006: Missing critical order identifiers */

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)
        AS missing_order_id,

    COUNT(*) FILTER (WHERE customer_id IS NULL)
        AS missing_customer_id
FROM bronze.olist_orders;


/* DQ-007: Do all orders map to a valid customer? */

SELECT COUNT(*) AS orphan_orders
FROM bronze.olist_orders o
LEFT JOIN bronze.olist_customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;



/********************************************************************
  SECTION 3 — ORDER ITEM DATA QUALITY
********************************************************************/


/* DQ-008: Duplicate order-item keys */

SELECT
    order_id,
    order_item_id,
    COUNT(*) AS duplicate_count
FROM bronze.olist_order_items
GROUP BY
    order_id,
    order_item_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;


/* DQ-009: Missing critical order-item identifiers */

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)
        AS missing_order_id,

    COUNT(*) FILTER (WHERE product_id IS NULL)
        AS missing_product_id,

    COUNT(*) FILTER (WHERE seller_id IS NULL)
        AS missing_seller_id
FROM bronze.olist_order_items;


/* DQ-010: Do all order items map to valid orders? */

SELECT COUNT(*) AS orphan_order_items
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;


/* DQ-011: Do all order items map to valid products? */

SELECT COUNT(*) AS orphan_product_references
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


/* DQ-012: Do all order items map to valid sellers? */

SELECT COUNT(*) AS orphan_seller_references
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


/* DQ-013: Are item prices valid? */

SELECT
    COUNT(*) AS invalid_price_records
FROM bronze.olist_order_items
WHERE price < 0
   OR price IS NULL;


/* DQ-014: Are freight values valid? */

SELECT
    COUNT(*) AS invalid_freight_records
FROM bronze.olist_order_items
WHERE freight_value < 0
   OR freight_value IS NULL;



/********************************************************************
  SECTION 4 — PAYMENT DATA QUALITY
********************************************************************/


/* DQ-015: Missing payment identifiers */

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)
        AS missing_order_id,

    COUNT(*) FILTER (WHERE payment_sequential IS NULL)
        AS missing_payment_sequence,

    COUNT(*) FILTER (WHERE payment_type IS NULL)
        AS missing_payment_type
FROM bronze.olist_order_payments;


/* DQ-016: Do payments map to valid orders? */

SELECT COUNT(*) AS orphan_payments
FROM bronze.olist_order_payments p
LEFT JOIN bronze.olist_orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;


/* DQ-017: Are payment values valid? */

SELECT
    COUNT(*) FILTER (WHERE payment_value < 0)
        AS negative_payment_values,

    COUNT(*) FILTER (WHERE payment_value IS NULL)
        AS missing_payment_values,

    COUNT(*) FILTER (WHERE payment_value = 0)
        AS zero_payment_values
FROM bronze.olist_order_payments;


/* DQ-018: Are payment types valid? */

SELECT DISTINCT payment_type
FROM bronze.olist_order_payments
ORDER BY payment_type;


/* DQ-019: Are payment installments valid? */

SELECT
    COUNT(*) AS invalid_installments
FROM bronze.olist_order_payments
WHERE payment_installments < 1
   OR payment_installments IS NULL;

SELECT *
FROM bronze.olist_order_payments
WHERE payment_installments < 1
   OR payment_installments IS NULL;

/********************************************************************
  SECTION 5 — REVIEW DATA QUALITY
********************************************************************/


/* DQ-020: Are review scores within the expected 1–5 range? */

SELECT
    COUNT(*) AS invalid_review_scores
FROM bronze.olist_order_reviews
WHERE review_score NOT BETWEEN 1 AND 5
   OR review_score IS NULL;


/* DQ-021: Missing review identifiers */

SELECT
    COUNT(*) FILTER (WHERE review_id IS NULL)
        AS missing_review_id,

    COUNT(*) FILTER (WHERE order_id IS NULL)
        AS missing_order_id
FROM bronze.olist_order_reviews;


/* DQ-022: Do reviews map to valid orders? */

SELECT COUNT(*) AS orphan_reviews
FROM bronze.olist_order_reviews r
LEFT JOIN bronze.olist_orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;


/* DQ-023: Duplicate review IDs */

SELECT
    review_id,
    COUNT(*) AS duplicate_count
FROM bronze.olist_order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;



/********************************************************************
  SECTION 6 — ORDER TIMESTAMP VALIDATION
********************************************************************/


/* DQ-024: Approved before purchase */

SELECT COUNT(*) AS invalid_approval_timestamps
FROM bronze.olist_orders
WHERE order_approved_at < order_purchase_timestamp;


/* DQ-025: Carrier delivery before approval */

SELECT COUNT(*) AS invalid_carrier_timestamps
FROM bronze.olist_orders
WHERE order_delivered_carrier_date < order_approved_at;


/* DQ-026: Customer delivery before carrier delivery */

SELECT COUNT(*) AS invalid_delivery_sequence
FROM bronze.olist_orders
WHERE order_delivered_customer_date
      < order_delivered_carrier_date;


/* DQ-027: Estimated delivery before purchase */

SELECT COUNT(*) AS invalid_estimated_delivery
FROM bronze.olist_orders
WHERE order_estimated_delivery_date
      < order_purchase_timestamp::date;


/* DQ-028: Delivery date before purchase */

SELECT COUNT(*) AS delivery_before_purchase
FROM bronze.olist_orders
WHERE order_delivered_customer_date
      < order_purchase_timestamp;



/********************************************************************
  SECTION 7 — ORDER STATUS / BUSINESS RULE VALIDATION
********************************************************************/


/* DQ-029: Delivered orders without customer delivery date */

SELECT COUNT(*) AS delivered_without_delivery_date
FROM bronze.olist_orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;


/* DQ-030: Delivered orders without carrier delivery date */

SELECT COUNT(*) AS delivered_without_carrier_date
FROM bronze.olist_orders
WHERE order_status = 'delivered'
  AND order_delivered_carrier_date IS NULL;


/* DQ-031: Canceled orders with customer delivery date */

SELECT COUNT(*) AS canceled_with_delivery_date
FROM bronze.olist_orders
WHERE order_status = 'canceled'
  AND order_delivered_customer_date IS NOT NULL;


/* DQ-032: Unavailable orders with customer delivery date */

SELECT COUNT(*) AS unavailable_with_delivery_date
FROM bronze.olist_orders
WHERE order_status = 'unavailable'
  AND order_delivered_customer_date IS NOT NULL;


/* DQ-033: Order statuses outside expected domain */

SELECT DISTINCT order_status
FROM bronze.olist_orders
ORDER BY order_status;



/********************************************************************
  SECTION 8 — PRODUCT DATA QUALITY
********************************************************************/


/* DQ-034: Are product IDs unique? */

SELECT
    COUNT(*) AS total_products,
    COUNT(DISTINCT product_id) AS distinct_product_ids,
    COUNT(*) - COUNT(DISTINCT product_id)
        AS duplicate_product_rows
FROM bronze.olist_products;


/* DQ-035: Missing product identifiers */

SELECT
    COUNT(*) FILTER (WHERE product_id IS NULL)
        AS missing_product_id
FROM bronze.olist_products;


/* DQ-036: Invalid product weights */

SELECT
    COUNT(*) FILTER (WHERE product_weight_g < 0)
        AS negative_weight,

    COUNT(*) FILTER (WHERE product_weight_g = 0)
        AS zero_weight,

    COUNT(*) FILTER (WHERE product_weight_g IS NULL)
        AS missing_weight
FROM bronze.olist_products;


/* DQ-037: Invalid product dimensions */

SELECT
    COUNT(*) FILTER (WHERE product_length_cm <= 0)
        AS invalid_length,

    COUNT(*) FILTER (WHERE product_height_cm <= 0)
        AS invalid_height,

    COUNT(*) FILTER (WHERE product_width_cm <= 0)
        AS invalid_width
FROM bronze.olist_products;


/* DQ-038: Missing product categories */

SELECT
    COUNT(*) AS missing_category
FROM bronze.olist_products
WHERE product_category_name IS NULL;



/********************************************************************
  SECTION 9 — SELLER DATA QUALITY
********************************************************************/


/* DQ-039: Are seller IDs unique? */

SELECT
    COUNT(*) AS total_sellers,
    COUNT(DISTINCT seller_id) AS distinct_sellers,
    COUNT(*) - COUNT(DISTINCT seller_id)
        AS duplicate_seller_rows
FROM bronze.olist_sellers;


/* DQ-040: Missing seller identifiers */

SELECT
    COUNT(*) FILTER (WHERE seller_id IS NULL)
        AS missing_seller_id
FROM bronze.olist_sellers;


/* DQ-041: Missing seller geographic information */

SELECT
    COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL)
        AS missing_zip,

    COUNT(*) FILTER (WHERE seller_city IS NULL)
        AS missing_city,

    COUNT(*) FILTER (WHERE seller_state IS NULL)
        AS missing_state
FROM bronze.olist_sellers;



/********************************************************************
  SECTION 10 — GEOLOCATION DATA QUALITY
********************************************************************/


/* DQ-042: Missing geolocation fields */

SELECT
    COUNT(*) FILTER (
        WHERE geolocation_zip_code_prefix IS NULL
    ) AS missing_zip,

    COUNT(*) FILTER (
        WHERE geolocation_lat IS NULL
    ) AS missing_latitude,

    COUNT(*) FILTER (
        WHERE geolocation_lng IS NULL
    ) AS missing_longitude,

    COUNT(*) FILTER (
        WHERE geolocation_city IS NULL
    ) AS missing_city,

    COUNT(*) FILTER (
        WHERE geolocation_state IS NULL
    ) AS missing_state
FROM bronze.olist_geolocation;


/* DQ-043: Invalid latitude values */

SELECT COUNT(*) AS invalid_latitude
FROM bronze.olist_geolocation
WHERE geolocation_lat NOT BETWEEN -90 AND 90;


/* DQ-044: Invalid longitude values */

SELECT COUNT(*) AS invalid_longitude
FROM bronze.olist_geolocation
WHERE geolocation_lng NOT BETWEEN -180 AND 180;


/* DQ-045: Geographic consistency
           ZIP prefix mapped to multiple states */

SELECT
    geolocation_zip_code_prefix,
    COUNT(DISTINCT geolocation_state) AS state_count
FROM bronze.olist_geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT geolocation_state) > 1
ORDER BY state_count DESC;



/********************************************************************
  SECTION 11 — CATEGORY TRANSLATION QUALITY
********************************************************************/


/* DQ-046: Duplicate Portuguese category names */

SELECT
    product_category_name,
    COUNT(*) AS occurrences
FROM bronze.product_category_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1;


/* DQ-047: Missing category translations */

SELECT
    COUNT(*) FILTER (
        WHERE product_category_name IS NULL
    ) AS missing_portuguese_category,

    COUNT(*) FILTER (
        WHERE product_category_name_english IS NULL
    ) AS missing_english_category
FROM bronze.product_category_translation;


/* DQ-048: Products with categories missing from translation table */

SELECT COUNT(*) AS untranslated_product_categories
FROM bronze.olist_products p
LEFT JOIN bronze.product_category_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;



/********************************************************************
  SECTION 12 — CROSS-TABLE CONSISTENCY
********************************************************************/


/* DQ-049: Orders with no corresponding order items */

SELECT COUNT(*) AS orders_without_items
FROM bronze.olist_orders o
LEFT JOIN (
    SELECT DISTINCT order_id
    FROM bronze.olist_order_items
) oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;


/* DQ-050: Orders with no payment record */

SELECT COUNT(*) AS orders_without_payment
FROM bronze.olist_orders o
LEFT JOIN (
    SELECT DISTINCT order_id
    FROM bronze.olist_order_payments
) p
    ON o.order_id = p.order_id
WHERE p.order_id IS NULL;


/* DQ-051: Orders with no review */

SELECT COUNT(*) AS orders_without_review
FROM bronze.olist_orders o
LEFT JOIN (
    SELECT DISTINCT order_id
    FROM bronze.olist_order_reviews
) r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL;


/* DQ-052: Order-item sellers missing from seller table */

SELECT COUNT(DISTINCT oi.seller_id) AS missing_sellers
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


/* DQ-053: Order-item products missing from product table */

SELECT COUNT(DISTINCT oi.product_id) AS missing_products
FROM bronze.olist_order_items oi
LEFT JOIN bronze.olist_products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


/*Investigate DQ-025*/
SELECT
    order_status,
    COUNT(*) AS affected_orders
FROM bronze.olist_orders
WHERE order_delivered_carrier_date < order_approved_at
GROUP BY order_status
ORDER BY affected_orders DESC;


SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date
FROM bronze.olist_orders
WHERE order_delivered_carrier_date < order_approved_at
ORDER BY order_approved_at - order_delivered_carrier_date DESC
LIMIT 20;

/*Investigate DQ-023*/

SELECT
    review_id,
    COUNT(*) AS occurrences,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM bronze.olist_order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;

/*Investigate DQ-049*/
SELECT
    o.order_status,
    COUNT(*) AS orders_without_items
FROM bronze.olist_orders o
LEFT JOIN (
    SELECT DISTINCT order_id
    FROM bronze.olist_order_items
) oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

/********************************************************************
  END OF DATA QUALITY ASSESSMENT
********************************************************************/