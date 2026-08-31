/* ============================================================
   MANAGEMENT / CONSUMPTION LAYER
   ============================================================

   Purpose:
   Convert the customer-level Gold analytical tables into
   management-ready KPIs and views.

   Existing Gold tables used:
       gold.customer_intelligence
       gold.customer_experience

   Grain:
       Executive KPI table  -> One row for the entire business
       Management views     -> Aggregated management-level data

   No customer-level Gold tables are recreated here.
   ============================================================ */


/* ============================================================
   STEP 2
   EXECUTIVE KPI TABLE
   ============================================================

   One-row executive snapshot of the business.

   KPIs include:
       - Total customers
       - Total orders
       - Total revenue
       - Average order value
       - Repeat customers
       - Repeat customer rate
       - Repeat-customer revenue
       - Repeat-customer revenue share
       - Average customer value
       - Average delivery time
       - Average late-order rate
       - Average review score
       - Poor-experience rate
   ============================================================ */

DROP TABLE IF EXISTS gold.executive_kpis;

CREATE TABLE gold.executive_kpis AS

SELECT

    /* -------------------------
       Customer base
       ------------------------- */

    COUNT(*) AS total_customers,

    COUNT(*) FILTER (
        WHERE ci.frequency > 1
    ) AS repeat_customers,

    COUNT(*) FILTER (
        WHERE ci.frequency = 1
    ) AS one_time_customers,

    ROUND(
        100.0 *
        COUNT(*) FILTER (WHERE ci.frequency > 1)
        / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_customer_rate,


    /* -------------------------
       Orders and revenue
       ------------------------- */

    SUM(ci.frequency) AS total_orders,

    ROUND(
        SUM(ci.monetary_value)::numeric,
        2
    ) AS total_revenue,

    ROUND(
        (
            SUM(ci.monetary_value)
            / NULLIF(SUM(ci.frequency), 0)
        )::numeric,
        2
    ) AS average_order_value,

    ROUND(
        AVG(ci.monetary_value)::numeric,
        2
    ) AS average_customer_value,


    /* -------------------------
       Repeat-customer economics
       ------------------------- */

    ROUND(
        SUM(ci.monetary_value)
        FILTER (WHERE ci.frequency > 1)::numeric,
        2
    ) AS repeat_customer_revenue,

    ROUND(
        100.0 *
        SUM(ci.monetary_value)
        FILTER (WHERE ci.frequency > 1)
        / NULLIF(SUM(ci.monetary_value), 0),
        2
    ) AS repeat_customer_revenue_share,


    /* -------------------------
       Customer experience
       ------------------------- */

    ROUND(
        AVG(ce.average_delivery_days)::numeric,
        2
    ) AS average_delivery_days,

    ROUND(
        (AVG(ce.late_order_rate) * 100)::numeric,
        2
    ) AS average_late_order_rate_pct,

    ROUND(
        AVG(ce.average_review_score)::numeric,
        2
    ) AS average_review_score,

    ROUND(
        (
            100.0 *
            AVG(
                CASE
                    WHEN ce.poor_experience_flag = TRUE
                    THEN 1.0
                    ELSE 0.0
                END
            )
        )::numeric,
        2
    ) AS poor_experience_rate_pct

FROM gold.customer_intelligence ci

LEFT JOIN gold.customer_experience ce
    ON ci.customer_unique_id = ce.customer_unique_id;


/* Check the executive KPI table */

SELECT *
FROM gold.executive_kpis;


/* ============================================================
   STEP 3A
   CUSTOMER SEGMENT MANAGEMENT VIEW
   ============================================================

   Purpose:
       Understand the size, revenue contribution and purchasing
       behaviour of each customer segment.

   Grain:
       One row per customer segment.
   ============================================================ */

CREATE OR REPLACE VIEW gold.v_customer_segments AS

SELECT

    ci.customer_segment,

    COUNT(*) AS customers,

    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_percentage,

    ROUND(
        SUM(ci.monetary_value)::numeric,
        2
    ) AS total_revenue,

    ROUND(
        100.0 *
        SUM(ci.monetary_value)
        / SUM(SUM(ci.monetary_value)) OVER (),
        2
    ) AS revenue_percentage,

    ROUND(
        AVG(ci.monetary_value)::numeric,
        2
    ) AS average_customer_value,

    ROUND(
        AVG(ci.frequency)::numeric,
        2
    ) AS average_orders,

    ROUND(
        (
            SUM(ci.monetary_value)
            / NULLIF(SUM(ci.frequency), 0)
        )::numeric,
        2
    ) AS average_order_value,

    ROUND(
        AVG(ci.recency_days)::numeric,
        1
    ) AS average_recency_days

FROM gold.customer_intelligence ci

GROUP BY
    ci.customer_segment

ORDER BY
    total_revenue DESC;


/* ============================================================
   STEP 3B
   CUSTOMER TYPE PERFORMANCE VIEW
   ============================================================

   Purpose:
       Compare one-time customers with repeat customers.

   Grain:
       One row per customer type.
   ============================================================ */

CREATE OR REPLACE VIEW gold.v_customer_type_performance AS

SELECT

    CASE
        WHEN ci.frequency > 1
            THEN 'Repeat customer'
        ELSE 'One-time customer'
    END AS customer_type,

    COUNT(*) AS customers,

    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_percentage,

    ROUND(
        SUM(ci.monetary_value)::numeric,
        2
    ) AS total_revenue,

    ROUND(
        100.0 *
        SUM(ci.monetary_value)
        / SUM(SUM(ci.monetary_value)) OVER (),
        2
    ) AS revenue_percentage,

    ROUND(
        AVG(ci.monetary_value)::numeric,
        2
    ) AS average_customer_value,

    ROUND(
        AVG(ci.frequency)::numeric,
        2
    ) AS average_orders,

    ROUND(
        (
            SUM(ci.monetary_value)
            / NULLIF(SUM(ci.frequency), 0)
        )::numeric,
        2
    ) AS average_order_value

FROM gold.customer_intelligence ci

GROUP BY
    CASE
        WHEN ci.frequency > 1
            THEN 'Repeat customer'
        ELSE 'One-time customer'
    END

ORDER BY
    total_revenue DESC;


/* ============================================================
   STEP 3C
   REVENUE CONCENTRATION VIEW
   ============================================================

   Purpose:
       Measure how concentrated revenue is across customers.

   Customers are divided into five equal-sized groups based on
   monetary value.

   Quintile 5 = highest-value customers
   Quintile 1 = lowest-value customers

   Grain:
       One row per monetary quintile.
   ============================================================ */

CREATE OR REPLACE VIEW gold.v_revenue_concentration AS

WITH customer_quintiles AS (

    SELECT

        customer_unique_id,
        monetary_value,

        NTILE(5) OVER (
            ORDER BY monetary_value
        ) AS monetary_quintile

    FROM gold.customer_intelligence
)

SELECT

    monetary_quintile,

    COUNT(*) AS customers,

    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_percentage,

    ROUND(
        MIN(monetary_value)::numeric,
        2
    ) AS minimum_customer_value,

    ROUND(
        MAX(monetary_value)::numeric,
        2
    ) AS maximum_customer_value,

    ROUND(
        AVG(monetary_value)::numeric,
        2
    ) AS average_customer_value,

    ROUND(
        SUM(monetary_value)::numeric,
        2
    ) AS total_revenue,

    ROUND(
        100.0 *
        SUM(monetary_value)
        / SUM(SUM(monetary_value)) OVER (),
        2
    ) AS revenue_percentage

FROM customer_quintiles

GROUP BY
    monetary_quintile

ORDER BY
    monetary_quintile;


/* ============================================================
   STEP 3D
   CUSTOMER EXPERIENCE VIEW
   ============================================================

   Purpose:
       Compare customer experience across customer segments.

   This allows management to identify whether valuable customer
   segments are experiencing delivery or service problems.

   Grain:
       One row per customer segment.
   ============================================================ */

CREATE OR REPLACE VIEW gold.v_customer_experience AS

SELECT

    ci.customer_segment,

    COUNT(*) AS customers,

    ROUND(
        AVG(ce.average_delivery_days)::numeric,
        2
    ) AS average_delivery_days,

    ROUND(
        (AVG(ce.late_order_rate) * 100)::numeric,
        2
    ) AS average_late_order_rate_pct,

    ROUND(
        AVG(ce.average_review_score)::numeric,
        2
    ) AS average_review_score,

    ROUND(
        (
            100.0 *
            AVG(
                CASE
                    WHEN ce.poor_experience_flag = TRUE
                    THEN 1.0
                    ELSE 0.0
                END
            )
        )::numeric,
        2
    ) AS poor_experience_rate_pct

FROM gold.customer_intelligence ci

JOIN gold.customer_experience ce
    ON ci.customer_unique_id = ce.customer_unique_id

GROUP BY
    ci.customer_segment

ORDER BY
    average_review_score ASC;


/* ============================================================
   STEP 3E
   RETENTION OPPORTUNITY VIEW
   ============================================================

   Purpose:
       Identify customer segments that could be targeted for
       retention or repeat-purchase initiatives.

   Priority segments:
       - High-Value One-Time
       - Recent One-Time
       - Developing Repeat
       - Low-Value Inactive

   Grain:
       One row per actionable segment.
   ============================================================ */

CREATE OR REPLACE VIEW gold.v_retention_opportunities AS

SELECT

    ci.customer_segment,

    COUNT(*) AS customers,

    ROUND(
        SUM(ci.monetary_value)::numeric,
        2
    ) AS associated_revenue,

    ROUND(
        AVG(ci.monetary_value)::numeric,
        2
    ) AS average_customer_value,

    ROUND(
        AVG(ci.frequency)::numeric,
        2
    ) AS average_orders,

    ROUND(
        AVG(ci.recency_days)::numeric,
        1
    ) AS average_recency_days,

    ROUND(
        AVG(ce.average_delivery_days)::numeric,
        2
    ) AS average_delivery_days,

    ROUND(
        (AVG(ce.late_order_rate) * 100)::numeric,
        2
    ) AS average_late_order_rate_pct,

    ROUND(
        AVG(ce.average_review_score)::numeric,
        2
    ) AS average_review_score,

    ROUND(
        (
            100.0 *
            AVG(
                CASE
                    WHEN ce.poor_experience_flag = TRUE
                    THEN 1.0
                    ELSE 0.0
                END
            )
        )::numeric,
        2
    ) AS poor_experience_rate_pct

FROM gold.customer_intelligence ci

JOIN gold.customer_experience ce
    ON ci.customer_unique_id = ce.customer_unique_id

WHERE ci.customer_segment IN (
    'High-Value One-Time',
    'Recent One-Time',
    'Developing Repeat',
    'Low-Value Inactive'
)

GROUP BY
    ci.customer_segment

ORDER BY
    associated_revenue DESC;


/* ============================================================
   FINAL VALIDATION
   ============================================================

   Run these after creation to confirm that the management
   layer was created successfully.
   ============================================================ */

SELECT *
FROM gold.executive_kpis;

SELECT *
FROM gold.v_customer_segments;

SELECT *
FROM gold.v_customer_type_performance;

SELECT *
FROM gold.v_revenue_concentration;

SELECT *
FROM gold.v_customer_experience;

SELECT *
FROM gold.v_retention_opportunities;