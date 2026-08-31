/*====================================================================
  11_GOLD_CUSTOMER_EXPERIENCE.SQL

  Gold Layer
  Grain: one row per customer_unique_id

  Purpose:
    Build customer-level delivery and satisfaction metrics to
    investigate the relationship between fulfillment experience
    and customer satisfaction.
====================================================================*/


/********************************************************************
  0. DROP EXISTING TABLE
********************************************************************/

DROP TABLE IF EXISTS gold.customer_experience;


/********************************************************************
  1. CUSTOMER EXPERIENCE DATASET
********************************************************************/

CREATE TABLE gold.customer_experience AS

WITH customer_accounts AS (

    SELECT DISTINCT
        customer_id,
        customer_unique_id
    FROM silver.customers
),


customer_orders AS (

    SELECT

        ca.customer_unique_id,

        os.order_id,
        os.order_status,

        os.delivery_days,
        os.delivery_vs_estimate_days,

        os.delivered_late,

        os.average_item_price,

        os.average_payment_value,

        os.review_count,
        os.average_review_score,
        os.low_score_reviews,
        os.high_score_reviews

    FROM customer_accounts ca

    INNER JOIN gold.order_summary os
        ON ca.customer_id = os.customer_id
),


experience_summary AS (

    SELECT

        customer_unique_id,

        /*----------------------------------------------------------
          DELIVERY
        ----------------------------------------------------------*/

        COUNT(*) FILTER (
            WHERE delivery_days IS NOT NULL
        ) AS orders_with_delivery_data,

        AVG(delivery_days)
            FILTER (
                WHERE delivery_days IS NOT NULL
            ) AS average_delivery_days,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY delivery_days
            )
            FILTER (
                WHERE delivery_days IS NOT NULL
            ) AS median_delivery_days,

        COUNT(*) FILTER (
            WHERE delivered_late = TRUE
        ) AS late_orders,

        AVG(delivery_vs_estimate_days)
            FILTER (
                WHERE delivery_vs_estimate_days IS NOT NULL
            ) AS average_delivery_vs_estimate_days,

        /*----------------------------------------------------------
          SATISFACTION
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
            AS high_score_reviews

    FROM customer_orders

    GROUP BY customer_unique_id
)


/********************************************************************
  2. CREATE CUSTOMER EXPERIENCE METRICS
********************************************************************/

SELECT

    customer_unique_id,

    /*--------------------------------------------------------------
      DELIVERY METRICS
    --------------------------------------------------------------*/

    orders_with_delivery_data,

    average_delivery_days,

    median_delivery_days,

    late_orders,

    ROUND(CASE
        WHEN orders_with_delivery_data > 0
        THEN
            late_orders::NUMERIC
            / orders_with_delivery_data
        ELSE NULL
    END,2) AS late_order_rate,

    ROUND(average_delivery_vs_estimate_days,2) AS average_delivery_vs_estimate_days,

    /*--------------------------------------------------------------
      SATISFACTION METRICS
    --------------------------------------------------------------*/

    total_reviews,

    ROUND(average_review_score,2) as average_review_score,

    low_score_reviews,

    high_score_reviews,

    ROUND(CASE
        WHEN total_reviews > 0
        THEN
            low_score_reviews::NUMERIC
            / total_reviews
        ELSE NULL
    END,2) AS low_review_rate,

    /*--------------------------------------------------------------
      EXPERIENCE FLAGS
    --------------------------------------------------------------*/

    CASE
        WHEN late_orders > 0
        THEN TRUE
        ELSE FALSE
    END AS has_delivery_delay,

    CASE
        WHEN low_score_reviews > 0
        THEN TRUE
        ELSE FALSE
    END AS has_low_rating,

    /*--------------------------------------------------------------
      POOR EXPERIENCE FLAG

      Definition:
      Customer has BOTH:
        1. at least one late order
        2. at least one review of 1 or 2

      This is an operational segmentation flag, not a causal
      conclusion.
    --------------------------------------------------------------*/

    CASE
        WHEN late_orders > 0
             AND low_score_reviews > 0
        THEN TRUE
        ELSE FALSE
    END AS poor_experience_flag

FROM experience_summary;


/********************************************************************
  3. INDEX
********************************************************************/

CREATE UNIQUE INDEX idx_customer_experience_customer
    ON gold.customer_experience(customer_unique_id);


/********************************************************************
  4. VALIDATION
********************************************************************/

SELECT

    COUNT(*) AS customers,

    COUNT(DISTINCT customer_unique_id)
        AS distinct_customers,

    COUNT(*) -
        COUNT(DISTINCT customer_unique_id)
        AS duplicate_customers,

    COUNT(*) FILTER (
        WHERE average_delivery_days < 0
    ) AS negative_average_delivery,

    COUNT(*) FILTER (
        WHERE late_order_rate < 0
           OR late_order_rate > 1
    ) AS invalid_late_rates,

    COUNT(*) FILTER (
        WHERE average_review_score < 1
           OR average_review_score > 5
    ) AS invalid_review_scores,

    COUNT(*) FILTER (
        WHERE poor_experience_flag = TRUE
    ) AS poor_experience_customers

FROM gold.customer_experience;