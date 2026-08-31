/*====================================================================
  12_GOLD_CUSTOMER_INTELLIGENCE.SQL

  Grain:
      1 row per customer_unique_id

  Purpose:
      Consolidated customer intelligence layer.

  Includes:
      1. RFM metrics
      2. RFM scoring
      3. Customer opportunity segmentation
      4. Segment economics
      5. Customer experience analysis

  Design principle:
      The Olist dataset contains 96K+ unique customers but only 3.12%
      are repeat customers. Therefore, conventional RFM labels such
      as "Champions" are not used blindly. Segmentation explicitly
      distinguishes repeat customers from one-time customers.
====================================================================*/


/********************************************************************
  0. REMOVE PREVIOUS CUSTOMER INTELLIGENCE TABLE
********************************************************************/

DROP TABLE IF EXISTS gold.customer_intelligence;

/********************************************************************
  1. CREATE CUSTOMER INTELLIGENCE TABLE
********************************************************************/

CREATE TABLE gold.customer_intelligence AS

WITH

/*====================================================================
  1A. ANALYSIS DATE
====================================================================*/

analysis_date AS (

    SELECT

        MAX(last_purchase_timestamp)::DATE + 1
            AS analysis_date

    FROM gold.customer_360
),


/*====================================================================
  1B. BASE CUSTOMER METRICS
====================================================================*/

customer_base AS (

    SELECT

        c.customer_unique_id,

        a.analysis_date,

        /*------------------------------------------------------------
          RFM METRICS
        ------------------------------------------------------------*/

        (
            a.analysis_date
            - c.last_purchase_timestamp::DATE
        ) AS recency_days,

        c.total_orders AS frequency,

        c.total_payment_value AS monetary_value,

        /*------------------------------------------------------------
          CUSTOMER 360 METRICS
        ------------------------------------------------------------*/

        c.delivered_orders,

        c.average_order_value,

        c.repeat_customer,

        c.customer_state,

        c.last_purchase_timestamp

    FROM gold.customer_360 c

    CROSS JOIN analysis_date a
),


/*====================================================================
  1C. RFM SCORING
====================================================================*/

rfm_scored AS (

    SELECT

        cb.*,

        /*------------------------------------------------------------
          RECENCY SCORE

          Lower recency_days = more recent = better.

          DESC ordering directly gives:
              5 = most recent
              1 = least recent
        ------------------------------------------------------------*/

        NTILE(5) OVER (
            ORDER BY recency_days DESC
        ) AS recency_score,

        /*------------------------------------------------------------
          FREQUENCY SCORE

              5 = highest frequency
              1 = lowest frequency
        ------------------------------------------------------------*/

        NTILE(5) OVER (
            ORDER BY frequency
        ) AS frequency_score,

        /*------------------------------------------------------------
          MONETARY SCORE

              5 = highest monetary value
              1 = lowest monetary value
        ------------------------------------------------------------*/

        NTILE(5) OVER (
            ORDER BY monetary_value
        ) AS monetary_score,

        /*------------------------------------------------------------
          MONETARY QUINTILE
        ------------------------------------------------------------*/

        NTILE(5) OVER (
            ORDER BY monetary_value
        ) AS monetary_quintile,

        /*------------------------------------------------------------
          RECENCY QUINTILE

          Higher = more recent.
        ------------------------------------------------------------*/

        6 - NTILE(5) OVER (
            ORDER BY recency_days
        ) AS recency_quintile

    FROM customer_base cb
),


/*====================================================================
  1D. CUSTOMER SEGMENTATION
====================================================================*/

segmented AS (

    SELECT

        rs.*,

        /*------------------------------------------------------------
          COMPOSITE RFM SCORE
        ------------------------------------------------------------*/

        (
            recency_score
            + frequency_score
            + monetary_score
        ) AS rfm_score,

        /*------------------------------------------------------------
          RFM CODE
        ------------------------------------------------------------*/

        CONCAT(
            recency_score,
            frequency_score,
            monetary_score
        ) AS rfm_code,

        /*------------------------------------------------------------
          OLIST-SPECIFIC CUSTOMER SEGMENTATION
        ------------------------------------------------------------*/

        CASE

            /*========================================================
              HIGH-VALUE REPEAT

              Repeat customer with high monetary value.
            ========================================================*/

            WHEN frequency >= 2
                 AND monetary_quintile >= 4
            THEN 'High-Value Repeat'


            /*========================================================
              DEVELOPING REPEAT

              Repeat customer but lower monetary value.
            ========================================================*/

            WHEN frequency >= 2
            THEN 'Developing Repeat'


            /*========================================================
              HIGH-VALUE ONE-TIME

              Large first purchase but no repeat purchase.

              Primary conversion opportunity.
            ========================================================*/

            WHEN frequency = 1
                 AND monetary_quintile >= 4
            THEN 'High-Value One-Time'


            /*========================================================
              RECENT ONE-TIME

              Recent first purchase.

              Early retention opportunity.
            ========================================================*/

            WHEN frequency = 1
                 AND recency_quintile >= 4
            THEN 'Recent One-Time'


            /*========================================================
              LOW-VALUE INACTIVE

              One purchase + low value + old purchase.
            ========================================================*/

            WHEN frequency = 1
                 AND monetary_quintile <= 2
                 AND recency_quintile <= 2
            THEN 'Low-Value Inactive'


            /*========================================================
              ESTABLISHED ONE-TIME

              Remaining one-time customers.
            ========================================================*/

            ELSE 'Established One-Time'

        END AS customer_segment

    FROM rfm_scored rs
)


/********************************************************************
  1E. FINAL CUSTOMER INTELLIGENCE TABLE
********************************************************************/

SELECT

    customer_unique_id,

    analysis_date,

    /*--------------------------------------------------------------
      CUSTOMER PROFILE
    --------------------------------------------------------------*/

    customer_state,

    last_purchase_timestamp,

    /*--------------------------------------------------------------
      RFM METRICS
    --------------------------------------------------------------*/

    recency_days,

    frequency,

    monetary_value,

    /*--------------------------------------------------------------
      RFM SCORES
    --------------------------------------------------------------*/

    recency_score,

    frequency_score,

    monetary_score,

    rfm_score,

    rfm_code,

    /*--------------------------------------------------------------
      QUINTILES
    --------------------------------------------------------------*/

    recency_quintile,

    monetary_quintile,

    /*--------------------------------------------------------------
      CUSTOMER STATUS
    --------------------------------------------------------------*/

    repeat_customer,

    delivered_orders,

    average_order_value,

    /*--------------------------------------------------------------
      BUSINESS SEGMENT
    --------------------------------------------------------------*/

    customer_segment

FROM segmented;


/********************************************************************
  2. INDEXES
********************************************************************/

CREATE UNIQUE INDEX idx_customer_intelligence_customer
    ON gold.customer_intelligence(customer_unique_id);

CREATE INDEX idx_customer_intelligence_segment
    ON gold.customer_intelligence(customer_segment);


/********************************************************************
  3. BASIC VALIDATION
********************************************************************/

SELECT

    COUNT(*) AS customers,

    COUNT(DISTINCT customer_unique_id)
        AS distinct_customers,

    MIN(recency_days)
        AS minimum_recency_days,

    MAX(recency_days)
        AS maximum_recency_days,

    MIN(frequency)
        AS minimum_frequency,

    MAX(frequency)
        AS maximum_frequency,

    MIN(monetary_value)
        AS minimum_monetary_value,

    MAX(monetary_value)
        AS maximum_monetary_value,

    MIN(recency_score)
        AS minimum_recency_score,

    MAX(recency_score)
        AS maximum_recency_score,

    MIN(frequency_score)
        AS minimum_frequency_score,

    MAX(frequency_score)
        AS maximum_frequency_score,

    MIN(monetary_score)
        AS minimum_monetary_score,

    MAX(monetary_score)
        AS maximum_monetary_score

FROM gold.customer_intelligence;


/********************************************************************
  4. CUSTOMER SEGMENT SUMMARY
====================================================================*/

SELECT

    customer_segment,

    COUNT(*) AS customers,

    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER () * 100,
        2
    ) AS customer_percentage,

    SUM(monetary_value) AS total_revenue,

    ROUND(
        SUM(monetary_value)
        / SUM(SUM(monetary_value)) OVER () * 100,
        2
    ) AS revenue_percentage,

    ROUND(
        AVG(monetary_value),
        2
    ) AS average_customer_value,

    ROUND(
        AVG(frequency),
        2
    ) AS average_frequency,

    ROUND(
        AVG(average_order_value),
        2
    ) AS average_order_value,

    ROUND(
        AVG(recency_days),
        1
    ) AS average_recency_days

FROM gold.customer_intelligence

GROUP BY customer_segment

ORDER BY total_revenue DESC;


/********************************************************************
  5. REPEAT VS ONE-TIME CUSTOMER ECONOMICS
********************************************************************/

SELECT

    CASE
        WHEN frequency = 1
        THEN 'One-time customer'
        ELSE 'Repeat customer'
    END AS customer_type,

    COUNT(*) AS customers,

    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER () * 100,
        2
    ) AS customer_percentage,

    SUM(monetary_value) AS total_revenue,

    ROUND(
        SUM(monetary_value)
        / SUM(SUM(monetary_value)) OVER () * 100,
        2
    ) AS revenue_percentage,

    ROUND(
        AVG(monetary_value),
        2
    ) AS average_customer_value,

    ROUND(
        AVG(frequency),
        2
    ) AS average_orders,

    ROUND(
        AVG(average_order_value),
        2
    ) AS average_order_value

FROM gold.customer_intelligence

GROUP BY

    CASE
        WHEN frequency = 1
        THEN 'One-time customer'
        ELSE 'Repeat customer'
    END

ORDER BY customers DESC;


/********************************************************************
  6. CUSTOMER SEGMENT × EXPERIENCE
********************************************************************/

SELECT

    ci.customer_segment,

    COUNT(*) AS customers,

    ROUND(
        AVG(ci.monetary_value),
        2
    ) AS average_customer_value,

    ROUND(
        AVG(ci.frequency),
        2
    ) AS average_orders,

    ROUND(
        AVG(ci.average_order_value),
        2
    ) AS average_order_value,

    ROUND(
        AVG(e.average_delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        AVG(e.late_order_rate) * 100,
        2
    ) AS average_late_order_rate,

    ROUND(
        AVG(e.average_review_score),
        2
    ) AS average_review_score,

    ROUND(
        AVG(
            CASE
                WHEN e.poor_experience_flag = TRUE
                THEN 1.0
                ELSE 0.0
            END
        ) * 100,
        2
    ) AS poor_experience_rate

FROM gold.customer_intelligence ci

LEFT JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

GROUP BY
    ci.customer_segment

ORDER BY
    average_customer_value DESC;


/********************************************************************
  7. REPEAT VS ONE-TIME × EXPERIENCE
********************************************************************/

SELECT

    CASE
        WHEN ci.frequency = 1
        THEN 'One-time'
        ELSE 'Repeat'
    END AS customer_type,

    COUNT(*) AS customers,

    ROUND(
        AVG(e.average_delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        AVG(e.late_order_rate) * 100,
        2
    ) AS average_late_order_rate,

    ROUND(
        AVG(e.average_review_score),
        2
    ) AS average_review_score,

    ROUND(
        AVG(
            CASE
                WHEN e.poor_experience_flag = TRUE
                THEN 1.0
                ELSE 0.0
            END
        ) * 100,
        2
    ) AS poor_experience_rate

FROM gold.customer_intelligence ci

LEFT JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

GROUP BY

    CASE
        WHEN ci.frequency = 1
        THEN 'One-time'
        ELSE 'Repeat'
    END

ORDER BY customer_type;


/********************************************************************
  8. HIGH-VALUE ONE-TIME CUSTOMER EXPERIENCE
********************************************************************/

SELECT

    COUNT(*) AS high_value_one_time_customers,

    SUM(ci.monetary_value) AS associated_revenue,

    ROUND(
        AVG(ci.monetary_value),
        2
    ) AS average_customer_value,

    ROUND(
        AVG(e.average_delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        AVG(e.late_order_rate) * 100,
        2
    ) AS average_late_order_rate,

    ROUND(
        AVG(e.average_review_score),
        2
    ) AS average_review_score,

    ROUND(
        AVG(
            CASE
                WHEN e.poor_experience_flag = TRUE
                THEN 1.0
                ELSE 0.0
            END
        ) * 100,
        2
    ) AS poor_experience_rate

FROM gold.customer_intelligence ci

JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

WHERE
    ci.customer_segment = 'High-Value One-Time';


/********************************************************************
  9. HIGH-VALUE ONE-TIME + POOR EXPERIENCE
********************************************************************/

SELECT

    COUNT(*) AS customers,

    SUM(ci.monetary_value) AS associated_revenue,

    ROUND(
        AVG(ci.monetary_value),
        2
    ) AS average_customer_value,

    ROUND(
        AVG(e.late_order_rate) * 100,
        2
    ) AS average_late_order_rate,

    ROUND(
        AVG(e.average_review_score),
        2
    ) AS average_review_score

FROM gold.customer_intelligence ci

JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

WHERE

    ci.customer_segment = 'High-Value One-Time'

    AND e.poor_experience_flag = TRUE;