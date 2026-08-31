/* ================================================================
   INVESTIGATION — HIGH-VALUE ONE-TIME + POOR EXPERIENCE
   ================================================================ */


/* 1A. Inspect anomalous customers */

SELECT
    ci.customer_unique_id,
    ci.customer_segment,
    ci.frequency,
    ci.monetary_value,
    e.average_delivery_days,
    e.late_order_rate,
    e.average_review_score,
    e.poor_experience_flag

FROM gold.customer_intelligence ci

JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

WHERE
    ci.customer_segment = 'High-Value One-Time'
    AND e.poor_experience_flag = TRUE

ORDER BY
    e.average_review_score ASC,
    e.late_order_rate DESC

LIMIT 50;


/* 1B. Distribution of experience metrics */

SELECT
    COUNT(*) AS customers,

    MIN(e.late_order_rate) AS minimum_late_rate,
    MAX(e.late_order_rate) AS maximum_late_rate,
    ROUND(AVG(e.late_order_rate), 2) AS average_late_rate,

    MIN(e.average_review_score) AS minimum_review_score,
    MAX(e.average_review_score) AS maximum_review_score,
    ROUND(AVG(e.average_review_score), 2) AS average_review_score,

    COUNT(*) FILTER (
        WHERE e.late_order_rate = 100
    ) AS customers_100pct_late,

    COUNT(*) FILTER (
        WHERE e.average_review_score <= 2
    ) AS customers_low_review

FROM gold.customer_intelligence ci

JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

WHERE
    ci.customer_segment = 'High-Value One-Time'
    AND e.poor_experience_flag = TRUE;


/* 1C. Check whether the anomaly is simply because
       these are one-order customers */

SELECT
    ci.frequency,
    COUNT(*) AS customers,

    ROUND(AVG(e.late_order_rate), 2) AS average_late_rate,
    ROUND(AVG(e.average_review_score), 2) AS average_review_score

FROM gold.customer_intelligence ci

JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

WHERE
    ci.customer_segment = 'High-Value One-Time'
    AND e.poor_experience_flag = TRUE

GROUP BY
    ci.frequency

ORDER BY
    ci.frequency;


/* 1D. Compare High-Value One-Time customers
       with and without poor experience */

SELECT
    e.poor_experience_flag,

    COUNT(*) AS customers,

    ROUND(AVG(ci.frequency), 2) AS average_frequency,
    ROUND(AVG(ci.monetary_value), 2) AS average_customer_value,
    ROUND(AVG(e.late_order_rate), 2) AS average_late_rate,
    ROUND(AVG(e.average_review_score), 2) AS average_review_score,
    ROUND(AVG(e.average_delivery_days), 2) AS average_delivery_days

FROM gold.customer_intelligence ci

JOIN gold.customer_experience e
    ON ci.customer_unique_id = e.customer_unique_id

WHERE
    ci.customer_segment = 'High-Value One-Time'

GROUP BY
    e.poor_experience_flag

ORDER BY
    e.poor_experience_flag;


/* ================================================================
   INVESTIGATION 2 — MONETARY VALUE DISTRIBUTION
   ================================================================ */

SELECT

    COUNT(*) AS customers,

    MIN(monetary_value) AS minimum_value,

    PERCENTILE_CONT(0.25)
    WITHIN GROUP (ORDER BY monetary_value)
    AS p25,

    PERCENTILE_CONT(0.50)
    WITHIN GROUP (ORDER BY monetary_value)
    AS median,

    PERCENTILE_CONT(0.75)
    WITHIN GROUP (ORDER BY monetary_value)
    AS p75,

    PERCENTILE_CONT(0.90)
    WITHIN GROUP (ORDER BY monetary_value)
    AS p90,

    PERCENTILE_CONT(0.95)
    WITHIN GROUP (ORDER BY monetary_value)
    AS p95,

    ROUND(MAX(monetary_value), 2) AS maximum_value

FROM gold.customer_intelligence;


/* Monetary quintiles */

SELECT

    monetary_quintile,

    COUNT(*) AS customers,

    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER () * 100,
        2
    ) AS customer_percentage,

    ROUND(MIN(monetary_value), 2) AS minimum_value,
    ROUND(MAX(monetary_value), 2) AS maximum_value,
    ROUND(AVG(monetary_value), 2) AS average_value,

    ROUND(SUM(monetary_value), 2) AS total_revenue,

    ROUND(
        SUM(monetary_value)
        / SUM(SUM(monetary_value)) OVER () * 100,
        2
    ) AS revenue_percentage

FROM gold.customer_intelligence

GROUP BY
    monetary_quintile

ORDER BY
    monetary_quintile;


/* ================================================================
   INVESTIGATION 3 — RECENCY DISTRIBUTION
   ================================================================ */

SELECT

    COUNT(*) AS customers,

    MIN(recency_days) AS minimum_recency,

    PERCENTILE_CONT(0.25)
        WITHIN GROUP (ORDER BY recency_days) AS p25,

    PERCENTILE_CONT(0.50)
        WITHIN GROUP (ORDER BY recency_days) AS median,

    PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY recency_days) AS p75,

    PERCENTILE_CONT(0.90)
        WITHIN GROUP (ORDER BY recency_days) AS p90,

    MAX(recency_days) AS maximum_recency

FROM gold.customer_intelligence;


/* Recency quintiles */

SELECT

    recency_quintile,

    COUNT(*) AS customers,

    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER () * 100,
        2
    ) AS customer_percentage,

    MIN(recency_days) AS minimum_recency,
    MAX(recency_days) AS maximum_recency,

    ROUND(AVG(recency_days), 1) AS average_recency

FROM gold.customer_intelligence

GROUP BY
    recency_quintile

ORDER BY
    recency_quintile;