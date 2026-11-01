-- =====================================================================
-- RedFlag — The Fraud Files | SQL Fraud Detection Project
-- Student: <Shaurya Kumar> | Batch: DA-DS-1
-- =====================================================================

USE redflag;

-- SELECT COUNT(*) AS redflag_transactions 
-- FROM redflag_transactions;
-- SELECT COUNT(DISTINCT user_id) AS unique_users 
-- FROM redflag_transactions;
-- SELECT 
-- 		MIN(txn_time) AS first_txn,
-- 		MAX(txn_time) AS last_txn 
--  FROM redflag_transactions;


-- =====================================================================
-- PATTERN 1: VELOCITY FRAUD
-- Signature: 30 or more transactions by one user on one calendar day.
-- Expected result: approximately 45–55 user-days (per project brief).
-- =====================================================================
SELECT
    user_id,
    DATE(txn_time) AS attack_date,
    COUNT(*) AS daily_txn_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY daily_txn_count DESC, user_id;


-- =====================================================================
-- PATTERN 2: ROUND-AMOUNT CLUSTERING
-- Signature: 15+ transactions with amounts from the specified round list.
-- Expected result: 25 users (per project brief).
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS round_amount_txn_count,
    SUM(amount) AS round_amount_total
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_amount_txn_count DESC, round_amount_total DESC;


-- =====================================================================
-- PATTERN 3: CARD TESTING
-- Signature: 30+ transactions below ₹10 by one user on one calendar day.
-- Expected result: 20 users (per project brief).
-- =====================================================================
SELECT
    user_id,
    DATE(txn_time) AS attack_date,
    COUNT(*) AS tiny_txn_count,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) AS failed_count,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY tiny_txn_count DESC, user_id;


-- =====================================================================
-- PATTERN 4: FAILED-THEN-SUCCEEDED (simplified signature)
-- Signature: 20+ failed transactions by one user.
-- Note: This is the simplified version described in the brief. The
-- advanced version requires pairing each failure with a later success
-- of the same amount within two minutes.
-- Expected result: 25 users (per project brief).
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS failed_txn_count,
    MIN(txn_time) AS first_failed_txn,
    MAX(txn_time) AS last_failed_txn
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 20
ORDER BY failed_txn_count DESC, user_id;


-- =====================================================================
-- PATTERN 5: ODD-HOUR CONCENTRATION
-- Signature: at least 30 total transactions and 80%+ between 02:00–04:59.
-- The brief defines this window as HOUR(txn_time) BETWEEN 2 AND 4.
-- Expected result: 20 users (per project brief).
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS total_txn_count,
    SUM(CASE
            WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
            ELSE 0
        END) AS odd_hour_txn_count,
    ROUND(
        100.0 * SUM(CASE
                        WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
                        ELSE 0
                    END) / COUNT(*),
        2
    ) AS odd_hour_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30
   AND SUM(CASE
               WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
               ELSE 0
           END) / COUNT(*) >= 0.80
ORDER BY odd_hour_percentage DESC, total_txn_count DESC;


-- =====================================================================
-- PATTERN 6: MULE ACCOUNTS (advanced signature)
-- Signature: at least 5 CREDIT transactions each followed within 30
-- minutes by a DEBIT of at least 70% of that CREDIT amount.
-- A debit can match more than one credit under this straightforward
-- interpretation; inspect matches if the instructor requires one-to-one
-- pairing.
-- Expected result: 30 users (per project brief).
-- =====================================================================
SELECT
    c.user_id,
    COUNT(*) AS qualifying_credit_count
FROM transactions AS c
WHERE c.txn_type = 'CREDIT'
  AND EXISTS (
      SELECT 1
      FROM transactions AS d
      WHERE d.user_id = c.user_id
        AND d.txn_type = 'DEBIT'
        AND d.txn_time >= c.txn_time
        AND d.txn_time <= DATE_ADD(c.txn_time, INTERVAL 30 MINUTE)
        AND d.amount >= 0.70 * c.amount
  )
GROUP BY c.user_id
HAVING COUNT(*) >= 5
ORDER BY qualifying_credit_count DESC, c.user_id;


-- =====================================================================
-- PATTERN 7: REFUND ABUSE
-- Signature: 20+ transactions and more than 40% are REFUND transactions.
-- Expected result: approximately 24–25 users (per project brief).
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS total_txn_count,
    SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) AS refund_count,
    ROUND(
        100.0 * SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS refund_percentage
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20
   AND SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) / COUNT(*) > 0.40
ORDER BY refund_percentage DESC, refund_count DESC;


-- =====================================================================
-- PATTERN 8: MERCHANT COLLUSION
-- Signature: top five users by transaction value account for >60% of
-- the merchant's total transaction value.
-- Uses CTEs and ROW_NUMBER(); requires MySQL 8.0+.
-- Expected result: 15 merchants (per project brief).
-- =====================================================================
WITH user_merchant_totals AS (
    SELECT
        merchant_id,
        user_id,
        SUM(amount) AS user_merchant_amount
    FROM transactions
    GROUP BY merchant_id, user_id
),
ranked_users AS (
    SELECT
        merchant_id,
        user_id,
        user_merchant_amount,
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id
            ORDER BY user_merchant_amount DESC, user_id
        ) AS user_rank
    FROM user_merchant_totals
),
merchant_totals AS (
    SELECT
        merchant_id,
        SUM(user_merchant_amount) AS merchant_total_amount
    FROM user_merchant_totals
    GROUP BY merchant_id
),
top_five_totals AS (
    SELECT
        merchant_id,
        SUM(user_merchant_amount) AS top_five_amount
    FROM ranked_users
    WHERE user_rank <= 5
    GROUP BY merchant_id
)
SELECT
    mt.merchant_id,
    mt.merchant_total_amount,
    COALESCE(tf.top_five_amount, 0) AS top_five_amount,
    ROUND(
        100.0 * COALESCE(tf.top_five_amount, 0) / mt.merchant_total_amount,
        2
    ) AS top_five_percentage
FROM merchant_totals AS mt
JOIN top_five_totals AS tf
    ON tf.merchant_id = mt.merchant_id
WHERE mt.merchant_total_amount > 0
  AND tf.top_five_amount / mt.merchant_total_amount > 0.60
ORDER BY top_five_percentage DESC, mt.merchant_id;


-- =====================================================================
-- PATTERN 9: JUST-UNDER-THRESHOLD / STRUCTURING
-- Signature: 10+ transactions at exactly ₹9,999.00 for one user.
-- Expected result: 20 users (per project brief).
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS just_under_threshold_count,
    SUM(amount) AS total_just_under_threshold_amount
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY just_under_threshold_count DESC, user_id;


-- =====================================================================
-- PATTERN 10: DORMANT-THEN-ACTIVE
-- Signature: a gap of at least 90 days between consecutive transactions,
-- followed by 15+ transactions after the later transaction in the gap.
-- Uses LAG() and a CTE; requires MySQL 8.0+.
-- Expected result: approximately 25–27 users (per project brief).
-- =====================================================================
WITH ordered_transactions AS (
    SELECT
        user_id,
        txn_id,
        txn_time,
        LAG(txn_time) OVER (
            PARTITION BY user_id
            ORDER BY txn_time, txn_id
        ) AS previous_txn_time
    FROM transactions
),
dormancy_gaps AS (
    SELECT
        user_id,
        txn_id,
        txn_time AS reactivation_time,
        previous_txn_time
    FROM ordered_transactions
    WHERE previous_txn_time IS NOT NULL
      AND txn_time >= DATE_ADD(previous_txn_time, INTERVAL 90 DAY)
),
post_gap_activity AS (
    SELECT
        g.user_id,
        g.reactivation_time,
        COUNT(t.txn_id) AS post_gap_txn_count
    FROM dormancy_gaps AS g
    JOIN transactions AS t
      ON t.user_id = g.user_id
     AND t.txn_time >= g.reactivation_time
    GROUP BY g.user_id, g.reactivation_time
)
SELECT
    user_id,
    reactivation_time,
    post_gap_txn_count
FROM post_gap_activity
WHERE post_gap_txn_count >= 15
ORDER BY post_gap_txn_count DESC, user_id, reactivation_time;


-- =====================================================================
-- PATTERN 11: VELOCITY SPIKE
-- Signature: peak monthly transaction count >=20 and >=5 times the
-- user's average monthly count across active months.
-- This follows the brief's monthly-count approach. If the instructor
-- expects all six calendar months (including zero-transaction months) in
-- the average, the calculation must be adjusted to include a calendar
-- month table.
-- Expected result: approximately 35–45 users (per project brief).
-- =====================================================================
WITH monthly_counts AS (
    SELECT
        user_id,
        DATE_FORMAT(txn_time, '%Y-%m') AS txn_month,
        COUNT(*) AS monthly_txn_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),
user_monthly_stats AS (
    SELECT
        user_id,
        MAX(monthly_txn_count) AS peak_monthly_count,
        AVG(monthly_txn_count) AS average_active_month_count
    FROM monthly_counts
    GROUP BY user_id
)
SELECT
    user_id,
    peak_monthly_count,
    ROUND(average_active_month_count, 2) AS average_active_month_count,
    ROUND(peak_monthly_count / average_active_month_count, 2) AS peak_to_average_ratio
FROM user_monthly_stats
WHERE peak_monthly_count >= 20
  AND peak_monthly_count >= 5 * average_active_month_count
ORDER BY peak_to_average_ratio DESC, peak_monthly_count DESC;


-- =====================================================================
-- PATTERN 12: GEOGRAPHIC IMPOSSIBILITY
-- Signature: consecutive transactions by a user occur in different
-- cities no more than 60 minutes apart.
-- Uses LAG() and TIMESTAMPDIFF();
-- Expected result: 15 users (per project brief).
-- =====================================================================
WITH ordered_transactions AS (
    SELECT
        txn_id,
        user_id,
        city,
        txn_time,
        LAG(city) OVER (
            PARTITION BY user_id
            ORDER BY txn_time, txn_id
        ) AS previous_city,
        LAG(txn_time) OVER (
            PARTITION BY user_id
            ORDER BY txn_time, txn_id
        ) AS previous_txn_time
    FROM transactions
)
SELECT
    user_id,
    txn_id,
    previous_city,
    city AS current_city,
    previous_txn_time,
    txn_time AS current_txn_time,
    TIMESTAMPDIFF(MINUTE, previous_txn_time, txn_time) AS minutes_between
FROM ordered_transactions
WHERE previous_txn_time IS NOT NULL
  AND previous_city <> city
  AND TIMESTAMPDIFF(MINUTE, previous_txn_time, txn_time) BETWEEN 0 AND 60
ORDER BY minutes_between, user_id, txn_time;

-- ===================================================================== --
