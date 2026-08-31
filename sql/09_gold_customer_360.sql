/*====================================================================
  09_GOLD_CUSTOMER_360.SQL

  Gold Layer
  Grain: one row per customer_unique_id

  Purpose:
    Build a business-ready Customer 360 dataset combining customer
    identity, transaction behaviour, value, experience, payments,
    and geography.

  IMPORTANT:
    customer_unique_id is the behavioural customer key.
====================================================================*/


/********************************************************************
  0. DROP EXISTING TABLE
********************************************************************/

DROP TABLE IF EXISTS gold.customer_360;


/********************************************************************
  1. CREATE CUSTOMER 360
********************************************************************/

CREATE TABLE gold.customer_360 AS

WITH customer_accounts AS (

    /*
      Map every customer account to its underlying customer.
    */

    SELECT DISTINCT
        customer_id,
        customer_unique_id
    FROM silver.customers
),


customer_orders AS (

    /*
      Bring order-level metrics to customer_unique_id.
    */

    SELECT

        ca.customer_unique_id,

        os.*

    FROM customer_accounts ca

    INNER JOIN gold.order_summary os
        ON ca.customer_id = os.customer_id
),


customer_summary AS (

    /*
      Aggregate all order-level metrics to customer grain.
    */

    SELECT

        customer_unique_id,

        /*----------------------------------------------------------
          PURCHASE ACTIVITY
        ----------------------------------------------------------*/

        COUNT(DISTINCT order_id)
            AS total_orders,

        COUNT(DISTINCT order_id) FILTER (
            WHERE order_status = 'delivered'
        ) AS delivered_orders,

        COUNT(DISTINCT order_id) FILTER (
            WHERE order_status IN (
                'canceled',
                'unavailable'
            )
        ) AS unsuccessful_orders,

        SUM(total_items)
            AS total_items,

        SUM(distinct_products)
            AS product_instances,

        /*----------------------------------------------------------
          CUSTOMER VALUE
        ----------------------------------------------------------*/

        SUM(order_item_value)
            AS total_merchandise_value,

        SUM(total_payment_value)
            AS total_payment_value,

        ROUND(AVG(total_payment_value),2)
            AS average_order_value,

        MAX(total_payment_value)
            AS maximum_order_value,

        SUM(freight_value)
            AS total_freight_value,

        /*----------------------------------------------------------
          CUSTOMER TIMING
        ----------------------------------------------------------*/

        MIN(order_purchase_timestamp)
            AS first_purchase_timestamp,

        MAX(order_purchase_timestamp)
            AS last_purchase_timestamp,

        /*----------------------------------------------------------
          DELIVERY EXPERIENCE
        ----------------------------------------------------------*/

        AVG(delivery_days)
            AS average_delivery_days,

        AVG(delivery_vs_estimate_days)
            AS average_delivery_vs_estimate_days,

        COUNT(*) FILTER (
            WHERE delivered_late = TRUE
        ) AS late_orders,

        COUNT(*) FILTER (
            WHERE delivery_days IS NOT NULL
        ) AS orders_with_delivery_data,

        /*----------------------------------------------------------
          CUSTOMER SATISFACTION
        ----------------------------------------------------------*/

        SUM(review_count)
            AS total_reviews,

        AVG(average_review_score)
            FILTER (
                WHERE average_review_score IS NOT NULL
            ) AS average_review_score,

        SUM(low_score_reviews)
            AS low_score_reviews,

        SUM(high_score_reviews)
            AS high_score_reviews,

        /*----------------------------------------------------------
          PAYMENT BEHAVIOUR
        ----------------------------------------------------------*/

        SUM(payment_records)
            AS total_payment_records,

        SUM(credit_card_payment_records)
            AS credit_card_payments,

        SUM(boleto_payment_records)
            AS boleto_payments,

        SUM(voucher_payment_records)
            AS voucher_payments,

        SUM(debit_card_payment_records)
            AS debit_card_payments,

        AVG(maximum_installments)
            AS average_max_installments

    FROM customer_orders

    GROUP BY customer_unique_id
)


/********************************************************************
  2. JOIN CUSTOMER PROFILE
********************************************************************/

SELECT

    cs.customer_unique_id,

    /*--------------------------------------------------------------
      GEOGRAPHY

      We select the most recent customer account's location.
      Since customer_unique_id can map to multiple customer_id values,
      we use the account associated with the latest purchase.
    --------------------------------------------------------------*/

    customer_profile.customer_city,
    customer_profile.customer_state,
    customer_profile.customer_zip_code_prefix,

    /*--------------------------------------------------------------
      CUSTOMER VALUE
    --------------------------------------------------------------*/

    cs.total_orders,
    cs.delivered_orders,
    cs.unsuccessful_orders,

    cs.total_items,

    cs.product_instances,

    cs.total_merchandise_value,
    cs.total_payment_value,

    cs.average_order_value,
    cs.maximum_order_value,

    cs.total_freight_value,

    /*--------------------------------------------------------------
      PURCHASE TIMING
    --------------------------------------------------------------*/

    cs.first_purchase_timestamp,
    cs.last_purchase_timestamp,

    EXTRACT(
        DAY FROM (
            cs.last_purchase_timestamp
            - cs.first_purchase_timestamp
        )
    ) AS customer_activity_days,

    /*--------------------------------------------------------------
      REPEAT CUSTOMER FLAG
    --------------------------------------------------------------*/

    CASE
        WHEN cs.total_orders >= 2
        THEN TRUE
        ELSE FALSE
    END AS repeat_customer,

    /*--------------------------------------------------------------
      PURCHASE FREQUENCY
    --------------------------------------------------------------*/

    CASE
        WHEN EXTRACT(
            DAY FROM (
                cs.last_purchase_timestamp
                - cs.first_purchase_timestamp
            )
        ) > 0
        THEN
            cs.total_orders /
            (
                EXTRACT(
                    DAY FROM (
                        cs.last_purchase_timestamp
                        - cs.first_purchase_timestamp
                    )
                ) / 30.0
            )
        ELSE NULL
    END AS orders_per_month,

    /*--------------------------------------------------------------
      DELIVERY EXPERIENCE
    --------------------------------------------------------------*/

    cs.average_delivery_days,
    cs.average_delivery_vs_estimate_days,
    cs.late_orders,
    cs.orders_with_delivery_data,

    CASE
        WHEN cs.orders_with_delivery_data > 0
        THEN
            cs.late_orders::NUMERIC
            / cs.orders_with_delivery_data
        ELSE NULL
    END AS late_order_rate,

    /*--------------------------------------------------------------
      CUSTOMER SATISFACTION
    --------------------------------------------------------------*/

    cs.total_reviews,
    cs.average_review_score,
    cs.low_score_reviews,
    cs.high_score_reviews,

    CASE
        WHEN cs.total_reviews > 0
        THEN
            cs.low_score_reviews::NUMERIC
            / cs.total_reviews
        ELSE NULL
    END AS low_review_rate,

    /*--------------------------------------------------------------
      PAYMENT BEHAVIOUR
    --------------------------------------------------------------*/

    cs.total_payment_records,
    cs.credit_card_payments,
    cs.boleto_payments,
    cs.voucher_payments,
    cs.debit_card_payments,

    cs.average_max_installments,

    /*--------------------------------------------------------------
      PAYMENT PREFERENCE
    --------------------------------------------------------------*/

    CASE
        WHEN cs.credit_card_payments >=
             GREATEST(
                 cs.boleto_payments,
                 cs.voucher_payments,
                 cs.debit_card_payments
             )
        THEN 'credit_card'

        WHEN cs.boleto_payments >=
             GREATEST(
                 cs.credit_card_payments,
                 cs.voucher_payments,
                 cs.debit_card_payments
             )
        THEN 'boleto'

        WHEN cs.voucher_payments >=
             GREATEST(
                 cs.credit_card_payments,
                 cs.boleto_payments,
                 cs.debit_card_payments
             )
        THEN 'voucher'

        ELSE 'debit_card'
    END AS primary_payment_method

FROM customer_summary cs

LEFT JOIN LATERAL (

    /*
      Select the customer account corresponding to the
      latest purchase.
    */

    SELECT
        c.customer_city,
        c.customer_state,
        c.customer_zip_code_prefix

    FROM silver.customers c

    INNER JOIN gold.order_summary os
        ON c.customer_id = os.customer_id

    WHERE c.customer_unique_id = cs.customer_unique_id

    ORDER BY os.order_purchase_timestamp DESC

    LIMIT 1

) customer_profile

ON TRUE;


/********************************************************************
  3. INDEX
********************************************************************/

CREATE UNIQUE INDEX idx_customer_360_unique_id
    ON gold.customer_360(customer_unique_id);

CREATE INDEX idx_customer_360_state
    ON gold.customer_360(customer_state);


/********************************************************************
  4. VALIDATION
********************************************************************/

SELECT

    COUNT(*) AS total_customers,

    COUNT(DISTINCT customer_unique_id)
        AS distinct_customers,

    COUNT(*) -
        COUNT(DISTINCT customer_unique_id)
        AS duplicate_customers,

    COUNT(*) FILTER (
        WHERE total_orders >= 2
    ) AS repeat_customers,

    COUNT(*) FILTER (
        WHERE total_orders = 1
    ) AS one_time_customers

FROM gold.customer_360;