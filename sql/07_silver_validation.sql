/*====================================================================
  07_SILVER_VALIDATION.SQL

  Purpose:
    Validate the Silver layer after transformation.
====================================================================*/


/********************************************************************
  1. ROW-COUNT RECONCILIATION
********************************************************************/

SELECT
    'customers' AS table_name,
    (SELECT COUNT(*) FROM bronze.olist_customers) AS bronze_rows,
    (SELECT COUNT(*) FROM silver.customers) AS silver_rows,
    (SELECT COUNT(*) FROM silver.customers)
      - (SELECT COUNT(*) FROM bronze.olist_customers) AS difference

UNION ALL

SELECT
    'orders',
    (SELECT COUNT(*) FROM bronze.olist_orders),
    (SELECT COUNT(*) FROM silver.orders),
    (SELECT COUNT(*) FROM silver.orders)
      - (SELECT COUNT(*) FROM bronze.olist_orders)

UNION ALL

SELECT
    'order_items',
    (SELECT COUNT(*) FROM bronze.olist_order_items),
    (SELECT COUNT(*) FROM silver.order_items),
    (SELECT COUNT(*) FROM silver.order_items)
      - (SELECT COUNT(*) FROM bronze.olist_order_items)

UNION ALL

SELECT
    'payments',
    (SELECT COUNT(*) FROM bronze.olist_order_payments),
    (SELECT COUNT(*) FROM silver.payments),
    (SELECT COUNT(*) FROM silver.payments)
      - (SELECT COUNT(*) FROM bronze.olist_order_payments)

UNION ALL

SELECT
    'reviews',
    (SELECT COUNT(*) FROM bronze.olist_order_reviews),
    (SELECT COUNT(*) FROM silver.reviews),
    (SELECT COUNT(*) FROM silver.reviews)
      - (SELECT COUNT(*) FROM bronze.olist_order_reviews)

UNION ALL

SELECT
    'products',
    (SELECT COUNT(*) FROM bronze.olist_products),
    (SELECT COUNT(*) FROM silver.products),
    (SELECT COUNT(*) FROM silver.products)
      - (SELECT COUNT(*) FROM bronze.olist_products)

UNION ALL

SELECT
    'sellers',
    (SELECT COUNT(*) FROM bronze.olist_sellers),
    (SELECT COUNT(*) FROM silver.sellers),
    (SELECT COUNT(*) FROM silver.sellers)
      - (SELECT COUNT(*) FROM bronze.olist_sellers)

UNION ALL

SELECT
    'geolocation',
    (SELECT COUNT(DISTINCT LPAD(
        CAST(geolocation_zip_code_prefix AS TEXT), 5, '0'
    )) FROM bronze.olist_geolocation),
    (SELECT COUNT(*) FROM silver.geolocation),
    (SELECT COUNT(*) FROM silver.geolocation)
      -
    (SELECT COUNT(DISTINCT LPAD(
        CAST(geolocation_zip_code_prefix AS TEXT), 5, '0'
    )) FROM bronze.olist_geolocation);


/********************************************************************
  2. CUSTOMER KEY VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(*) - COUNT(DISTINCT customer_id)
        AS duplicate_customer_ids
FROM silver.customers;


/********************************************************************
  3. ORDER KEY VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id)
        AS duplicate_order_ids
FROM silver.orders;


/********************************************************************
  4. ORDER ITEM KEY VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT (order_id, order_item_id))
        AS distinct_order_item_keys,
    COUNT(*) -
        COUNT(DISTINCT (order_id, order_item_id))
        AS duplicate_order_item_keys
FROM silver.order_items;


/********************************************************************
  5. PRODUCT KEY VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_id) AS distinct_product_ids,
    COUNT(*) - COUNT(DISTINCT product_id)
        AS duplicate_product_ids
FROM silver.products;


/********************************************************************
  6. SELLER KEY VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT seller_id) AS distinct_seller_ids,
    COUNT(*) - COUNT(DISTINCT seller_id)
        AS duplicate_seller_ids
FROM silver.sellers;


/********************************************************************
  7. REVIEW KEY VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT (review_id, order_id))
        AS distinct_review_keys,
    COUNT(*) -
        COUNT(DISTINCT (review_id, order_id))
        AS duplicate_review_keys
FROM silver.reviews;


/********************************************************************
  8. ORDER → CUSTOMER REFERENTIAL INTEGRITY
********************************************************************/

SELECT COUNT(*) AS orphan_orders
FROM silver.orders o
LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


/********************************************************************
  9. ORDER ITEM → ORDER REFERENTIAL INTEGRITY
********************************************************************/

SELECT COUNT(*) AS orphan_order_items
FROM silver.order_items oi
LEFT JOIN silver.orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;


/********************************************************************
  10. ORDER ITEM → PRODUCT REFERENTIAL INTEGRITY
********************************************************************/

SELECT COUNT(*) AS orphan_products
FROM silver.order_items oi
LEFT JOIN silver.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


/********************************************************************
  11. ORDER ITEM → SELLER REFERENTIAL INTEGRITY
********************************************************************/

SELECT COUNT(*) AS orphan_sellers
FROM silver.order_items oi
LEFT JOIN silver.sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


/********************************************************************
  12. PAYMENT → ORDER REFERENTIAL INTEGRITY
********************************************************************/

SELECT COUNT(*) AS orphan_payments
FROM silver.payments p
LEFT JOIN silver.orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;


/********************************************************************
  13. REVIEW → ORDER REFERENTIAL INTEGRITY
********************************************************************/

SELECT COUNT(*) AS orphan_reviews
FROM silver.reviews r
LEFT JOIN silver.orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;


/********************************************************************
  14. ZIP CODE STANDARDIZATION
********************************************************************/

SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (
        WHERE customer_zip_code_prefix IS NULL
    ) AS null_zip_codes,
    COUNT(*) FILTER (
        WHERE LENGTH(customer_zip_code_prefix) <> 5
    ) AS invalid_zip_length
FROM silver.customers;


/********************************************************************
  15. SELLER ZIP STANDARDIZATION
********************************************************************/

SELECT
    COUNT(*) AS total_sellers,
    COUNT(*) FILTER (
        WHERE seller_zip_code_prefix IS NULL
    ) AS null_zip_codes,
    COUNT(*) FILTER (
        WHERE LENGTH(seller_zip_code_prefix) <> 5
    ) AS invalid_zip_length
FROM silver.sellers;


/********************************************************************
  16. PAYMENT ANOMALY FLAG
********************************************************************/

SELECT
    COUNT(*) AS total_payments,
    COUNT(*) FILTER (
        WHERE invalid_installment_flag = TRUE
    ) AS flagged_installment_records
FROM silver.payments;


/********************************************************************
  17. ORDER TIMESTAMP ANOMALIES
********************************************************************/

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE approval_carrier_timestamp_anomaly = TRUE
    ) AS approval_carrier_anomalies,

    COUNT(*) FILTER (
        WHERE delivery_sequence_anomaly = TRUE
    ) AS delivery_sequence_anomalies

FROM silver.orders;


/********************************************************************
  18. PRODUCT CATEGORY COMPLETENESS
********************************************************************/

SELECT
    COUNT(*) AS total_products,

    COUNT(*) FILTER (
        WHERE product_category_name = 'unknown'
    ) AS unknown_original_category,

    COUNT(*) FILTER (
        WHERE product_category_name_english = 'unknown'
    ) AS unknown_english_category

FROM silver.products;


/********************************************************************
  19. GEOLOCATION VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS zip_prefixes,
    COUNT(*) FILTER (
        WHERE geographic_ambiguity_flag = TRUE
    ) AS ambiguous_zip_prefixes
FROM silver.geolocation;


/********************************************************************
  20. DELIVERY METRIC VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE delivery_days IS NOT NULL
    ) AS valid_delivery_days,

    COUNT(*) FILTER (
        WHERE delivery_days < 0
    ) AS negative_delivery_days,

    MIN(delivery_days) AS minimum_delivery_days,
    MAX(delivery_days) AS maximum_delivery_days,
    AVG(delivery_days) AS average_delivery_days

FROM silver.orders;


/********************************************************************
  21. SILVER VALIDATION SUMMARY
********************************************************************/

SELECT
    'Silver layer validation complete' AS validation_status,
    CURRENT_TIMESTAMP AS validation_timestamp;