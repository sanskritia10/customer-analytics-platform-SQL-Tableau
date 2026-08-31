/*====================================================================
  08_GOLD_ORDER_SUMMARY.SQL

  Gold Layer
  Grain: one row per order_id

  Purpose:
    Create a business-ready order-level analytical table by
    aggregating all lower-grain transactional tables before joining.
====================================================================*/


/********************************************************************
  0. CREATE GOLD SCHEMA
********************************************************************/

CREATE SCHEMA IF NOT EXISTS gold;


/********************************************************************
  1. DROP EXISTING TABLE
********************************************************************/

DROP TABLE IF EXISTS gold.order_summary;


/********************************************************************
  2. CREATE ORDER-LEVEL ANALYTICAL DATASET
********************************************************************/

CREATE TABLE gold.order_summary AS

WITH

/*---------------------------------------------------------------
  ORDER ITEMS AGGREGATION
---------------------------------------------------------------*/

item_summary AS (

    SELECT
        order_id,

        COUNT(*) AS total_items,

        COUNT(DISTINCT product_id)
            AS distinct_products,

        COUNT(DISTINCT seller_id)
            AS distinct_sellers,

        SUM(price) AS merchandise_value,

        SUM(freight_value) AS freight_value,

        SUM(item_total_value) AS order_item_value,

        AVG(price) AS average_item_price,

        MAX(price) AS maximum_item_price

    FROM silver.order_items

    GROUP BY order_id
),


/*---------------------------------------------------------------
  PAYMENT AGGREGATION
---------------------------------------------------------------*/

payment_summary AS (

    SELECT
        order_id,

        COUNT(*) AS payment_records,

        SUM(payment_value) AS total_payment_value,

        AVG(payment_value) AS average_payment_value,

        MAX(payment_value) AS maximum_payment_value,

        MAX(payment_installments)
            AS maximum_installments,

        COUNT(*) FILTER (
            WHERE payment_type = 'credit_card'
        ) AS credit_card_payment_records,

        COUNT(*) FILTER (
            WHERE payment_type = 'boleto'
        ) AS boleto_payment_records,

        COUNT(*) FILTER (
            WHERE payment_type = 'voucher'
        ) AS voucher_payment_records,

        COUNT(*) FILTER (
            WHERE payment_type = 'debit_card'
        ) AS debit_card_payment_records

    FROM silver.payments

    GROUP BY order_id
),


/*---------------------------------------------------------------
  REVIEW AGGREGATION

  Reviews are aggregated before joining to prevent fan-out.
---------------------------------------------------------------*/

review_summary AS (

    SELECT
        order_id,

        COUNT(*) AS review_count,

        ROUND(AVG(review_score),2) AS average_review_score,

        COUNT(*) FILTER (
            WHERE review_score <= 2
        ) AS low_score_reviews,

        COUNT(*) FILTER (
            WHERE review_score >= 4
        ) AS high_score_reviews,

        COUNT(*) FILTER (
            WHERE review_comment_message IS NOT NULL
        ) AS reviews_with_message

    FROM silver.reviews

    GROUP BY order_id
)


/********************************************************************
  3. JOIN TO ORDER GRAIN
********************************************************************/

SELECT

    /*-------------------------------------------------------------
      ORDER IDENTIFIERS
    -------------------------------------------------------------*/

    o.order_id,
    o.customer_id,

    /*-------------------------------------------------------------
      ORDER STATUS
    -------------------------------------------------------------*/

    o.order_status,

    /*-------------------------------------------------------------
      ORDER TIMING
    -------------------------------------------------------------*/

    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    /*-------------------------------------------------------------
      DELIVERY PERFORMANCE
    -------------------------------------------------------------*/

    o.delivery_days,
    o.delivery_vs_estimate_days,

    CASE
        WHEN o.delivery_vs_estimate_days > 0
        THEN TRUE
        WHEN o.delivery_vs_estimate_days IS NOT NULL
        THEN FALSE
        ELSE NULL
    END AS delivered_late,

    o.approval_carrier_timestamp_anomaly,
    o.delivery_sequence_anomaly,

    /*-------------------------------------------------------------
      ITEM METRICS
    -------------------------------------------------------------*/

    COALESCE(i.total_items, 0)
        AS total_items,

    COALESCE(i.distinct_products, 0)
        AS distinct_products,

    COALESCE(i.distinct_sellers, 0)
        AS distinct_sellers,

    COALESCE(i.merchandise_value, 0)
        AS merchandise_value,

    COALESCE(i.freight_value, 0)
        AS freight_value,

    COALESCE(i.order_item_value, 0)
        AS order_item_value,

    i.average_item_price,
    i.maximum_item_price,

    /*-------------------------------------------------------------
      PAYMENT METRICS
    -------------------------------------------------------------*/

    COALESCE(p.payment_records, 0)
        AS payment_records,

    COALESCE(p.total_payment_value, 0)
        AS total_payment_value,

    p.average_payment_value,
    p.maximum_payment_value,
    p.maximum_installments,

    COALESCE(p.credit_card_payment_records, 0)
        AS credit_card_payment_records,

    COALESCE(p.boleto_payment_records, 0)
        AS boleto_payment_records,

    COALESCE(p.voucher_payment_records, 0)
        AS voucher_payment_records,

    COALESCE(p.debit_card_payment_records, 0)
        AS debit_card_payment_records,

    /*-------------------------------------------------------------
      REVIEW METRICS
    -------------------------------------------------------------*/

    COALESCE(r.review_count, 0)
        AS review_count,

    r.average_review_score,

    COALESCE(r.low_score_reviews, 0)
        AS low_score_reviews,

    COALESCE(r.high_score_reviews, 0)
        AS high_score_reviews,

    COALESCE(r.reviews_with_message, 0)
        AS reviews_with_message

FROM silver.orders o

LEFT JOIN item_summary i
    ON o.order_id = i.order_id

LEFT JOIN payment_summary p
    ON o.order_id = p.order_id

LEFT JOIN review_summary r
    ON o.order_id = r.order_id;


/********************************************************************
  4. CREATE INDEX
********************************************************************/

CREATE UNIQUE INDEX idx_gold_order_summary_order_id
    ON gold.order_summary(order_id);

CREATE INDEX idx_gold_order_summary_customer_id
    ON gold.order_summary(customer_id);


/********************************************************************
  5. VALIDATION
********************************************************************/

SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(*) - COUNT(DISTINCT order_id)
        AS duplicate_orders
FROM gold.order_summary;