/*====================================================================
  10_GOLD_CUSTOMER_CATEGORY_BEHAVIOR.SQL

  Gold Layer
  Grain: one row per customer_unique_id × product_category

  Purpose:
    Understand customer purchasing preferences and category-level
    customer value without compromising the grain of customer_360.
====================================================================*/


/********************************************************************
  0. DROP EXISTING TABLE
********************************************************************/

DROP TABLE IF EXISTS gold.customer_category_behavior;


/********************************************************************
  1. BUILD CUSTOMER-CATEGORY DATASET
********************************************************************/

CREATE TABLE gold.customer_category_behavior AS

WITH customer_orders AS (

    /*
      Map order items to the underlying customer.
    */

    SELECT

        c.customer_unique_id,

        oi.order_id,
        oi.product_id,

        p.product_category_name,
        p.product_category_name_english,

        oi.price,
        oi.freight_value

    FROM silver.order_items oi

    INNER JOIN silver.orders o
        ON oi.order_id = o.order_id

    INNER JOIN silver.customers c
        ON o.customer_id = c.customer_id

    LEFT JOIN silver.products p
        ON oi.product_id = p.product_id
),


category_summary AS (

    SELECT

        customer_unique_id,

        COALESCE(
            product_category_name_english,
            'unknown'
        ) AS product_category,

        COUNT(DISTINCT order_id)
            AS category_orders,

        COUNT(*) AS category_items,

        COUNT(DISTINCT product_id)
            AS distinct_products,

        SUM(price)
            AS category_merchandise_value,

        SUM(freight_value)
            AS category_freight_value,

        AVG(price)
            AS average_item_price

    FROM customer_orders

    GROUP BY
        customer_unique_id,
        COALESCE(
            product_category_name_english,
            'unknown'
        )
)


/********************************************************************
  2. ADD CUSTOMER-LEVEL CATEGORY METRICS
********************************************************************/

SELECT

    customer_unique_id,

    product_category,

    category_orders,
    category_items,
    distinct_products,

    category_merchandise_value,
    category_freight_value,

    ROUND(average_item_price,2) as average_item_price,

    /*--------------------------------------------------------------
      CUSTOMER CATEGORY RANK
    --------------------------------------------------------------*/

    RANK() OVER (
        PARTITION BY customer_unique_id
        ORDER BY category_merchandise_value DESC
    ) AS category_value_rank,

    /*--------------------------------------------------------------
      CATEGORY SPEND SHARE
    --------------------------------------------------------------*/

    ROUND(category_merchandise_value
    /
    NULLIF(
        SUM(category_merchandise_value) OVER (
            PARTITION BY customer_unique_id
        ),
        0
    ),2) AS category_spend_share,

    /*--------------------------------------------------------------
      CATEGORY ORDER SHARE
    --------------------------------------------------------------*/

    ROUND(category_orders::NUMERIC
    /
    NULLIF(
        SUM(category_orders) OVER (
            PARTITION BY customer_unique_id
        ),
        0
    ),2) AS category_order_share

FROM category_summary;


/********************************************************************
  3. INDEX
********************************************************************/

CREATE INDEX idx_customer_category_customer
    ON gold.customer_category_behavior(customer_unique_id);

CREATE INDEX idx_customer_category_category
    ON gold.customer_category_behavior(product_category);


/********************************************************************
  4. VALIDATION
********************************************************************/

SELECT

    COUNT(*) AS customer_category_rows,

    COUNT(DISTINCT customer_unique_id)
        AS customers,

    COUNT(DISTINCT product_category)
        AS categories,

    COUNT(*) FILTER (
        WHERE category_spend_share < 0
    ) AS negative_spend_shares,

    COUNT(*) FILTER (
        WHERE category_spend_share > 1
    ) AS invalid_spend_shares,

    MIN(category_spend_share)
        AS minimum_spend_share,

    MAX(category_spend_share)
        AS maximum_spend_share

FROM gold.customer_category_behavior;