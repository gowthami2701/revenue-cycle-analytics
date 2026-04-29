-- ============================================================
-- Revenue Cycle Analytics - Database Schema & KPI Queries
-- Healthcare Data Analyst Portfolio Project
-- Author: Gowthami Vasamsetti
-- ============================================================

-- ── SCHEMA SETUP ──────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS revenue_cycle;
SET search_path TO revenue_cycle;

-- Claims fact table
CREATE TABLE claims (
    claim_id            VARCHAR(10) PRIMARY KEY,
    patient_id          VARCHAR(10) NOT NULL,
    service_date        DATE NOT NULL,
    submit_date         DATE NOT NULL,
    payment_date        DATE,
    provider            VARCHAR(100),
    department          VARCHAR(50),
    payer               VARCHAR(50),
    cpt_code            VARCHAR(10),
    cpt_description     VARCHAR(100),
    icd10_primary       VARCHAR(10),
    icd10_description   VARCHAR(200),
    charge_amount       DECIMAL(10,2),
    payment_amount      DECIMAL(10,2),
    adjustment_amount   DECIMAL(10,2),
    status              VARCHAR(20),
    denial_code         VARCHAR(10),
    denial_reason       VARCHAR(100),
    was_appealed        BOOLEAN DEFAULT FALSE,
    days_in_ar          INTEGER,
    service_month       VARCHAR(7),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for performance
CREATE INDEX idx_claims_service_date ON claims(service_date);
CREATE INDEX idx_claims_payer ON claims(payer);
CREATE INDEX idx_claims_status ON claims(status);
CREATE INDEX idx_claims_cpt ON claims(cpt_code);

-- ── KPI QUERIES ───────────────────────────────────────────────────────────────

-- ── 1. EXECUTIVE DASHBOARD KPIs ──

SELECT
    COUNT(*)                                                        AS total_claims,
    SUM(charge_amount)                                              AS total_charges,
    SUM(payment_amount)                                             AS total_payments,
    ROUND(SUM(payment_amount) / NULLIF(SUM(charge_amount),0) * 100, 2)
                                                                    AS net_collection_rate_pct,
    ROUND(AVG(CASE WHEN status = 'Denied' THEN 1.0 ELSE 0 END) * 100, 2)
                                                                    AS denial_rate_pct,
    ROUND(AVG(CASE WHEN status NOT IN ('Denied','Pending') AND was_appealed = FALSE THEN 1.0 ELSE 0 END) * 100, 2)
                                                                    AS first_pass_resolution_pct,
    ROUND(AVG(CASE WHEN status NOT IN ('Denied') THEN 1.0 ELSE 0 END) * 100, 2)
                                                                    AS clean_claim_rate_pct,
    ROUND(AVG(NULLIF(days_in_ar, 0)), 1)                           AS avg_days_in_ar
FROM claims
WHERE service_date >= CURRENT_DATE - INTERVAL '12 months';


-- ── 2. DENIAL ANALYSIS BY REASON ──

SELECT
    denial_code,
    denial_reason,
    COUNT(*)                                    AS denial_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2)
                                                AS pct_of_total_denials,
    SUM(charge_amount)                          AS revenue_at_risk,
    ROUND(AVG(charge_amount), 2)                AS avg_charge,
    SUM(CASE WHEN was_appealed THEN payment_amount ELSE 0 END)
                                                AS recovered_via_appeal
FROM claims
WHERE status = 'Denied'
  AND denial_code IS NOT NULL
GROUP BY denial_code, denial_reason
ORDER BY denial_count DESC;


-- ── 3. PAYER PERFORMANCE SCORECARD ──

SELECT
    payer,
    COUNT(*)                                    AS total_claims,
    SUM(charge_amount)                          AS total_charges,
    SUM(payment_amount)                         AS total_payments,
    ROUND(SUM(payment_amount)/NULLIF(SUM(charge_amount),0)*100, 2)
                                                AS collection_rate_pct,
    ROUND(AVG(CASE WHEN status='Denied' THEN 1.0 ELSE 0 END)*100, 2)
                                                AS denial_rate_pct,
    ROUND(AVG(NULLIF(days_in_ar,0)), 1)         AS avg_days_in_ar,
    SUM(CASE WHEN days_in_ar > 90 THEN charge_amount - payment_amount ELSE 0 END)
                                                AS ar_over_90_days
FROM claims
GROUP BY payer
ORDER BY denial_rate_pct DESC;


-- ── 4. AR AGING BUCKET ANALYSIS ──

SELECT
    payer,
    COUNT(CASE WHEN days_in_ar BETWEEN 0  AND 30  THEN 1 END)  AS "0-30 days",
    COUNT(CASE WHEN days_in_ar BETWEEN 31 AND 60  THEN 1 END)  AS "31-60 days",
    COUNT(CASE WHEN days_in_ar BETWEEN 61 AND 90  THEN 1 END)  AS "61-90 days",
    COUNT(CASE WHEN days_in_ar BETWEEN 91 AND 120 THEN 1 END)  AS "91-120 days",
    COUNT(CASE WHEN days_in_ar > 120              THEN 1 END)  AS ">120 days",
    SUM(CASE WHEN days_in_ar > 90 THEN charge_amount - payment_amount ELSE 0 END)
                                                               AS revenue_at_risk_over90
FROM claims
WHERE status NOT IN ('Paid')
GROUP BY payer
ORDER BY revenue_at_risk_over90 DESC;


-- ── 5. CPT CODE PERFORMANCE ──

SELECT
    cpt_code,
    cpt_description,
    COUNT(*)                                                AS total_claims,
    SUM(charge_amount)                                      AS total_charges,
    ROUND(AVG(CASE WHEN status='Denied' THEN 1.0 ELSE 0 END)*100, 2)
                                                            AS denial_rate_pct,
    ROUND(AVG(payment_amount / NULLIF(charge_amount,0))*100, 2)
                                                            AS avg_collection_pct,
    SUM(CASE WHEN status='Denied' THEN charge_amount ELSE 0 END)
                                                            AS denied_revenue
FROM claims
GROUP BY cpt_code, cpt_description
ORDER BY denial_rate_pct DESC;


-- ── 6. MONTHLY REVENUE TREND ──

SELECT
    service_month,
    COUNT(*)                                    AS claims_submitted,
    SUM(charge_amount)                          AS total_charges,
    SUM(payment_amount)                         AS total_payments,
    SUM(charge_amount) - SUM(payment_amount)    AS total_adjustments,
    ROUND(AVG(CASE WHEN status='Denied' THEN 1.0 ELSE 0 END)*100, 2)
                                                AS denial_rate_pct,
    -- Month-over-month payment change
    SUM(payment_amount) - LAG(SUM(payment_amount)) OVER (ORDER BY service_month)
                                                AS mom_payment_change,
    ROUND(
        (SUM(payment_amount) - LAG(SUM(payment_amount)) OVER (ORDER BY service_month))
        / NULLIF(LAG(SUM(payment_amount)) OVER (ORDER BY service_month), 0) * 100
    , 2)                                        AS mom_change_pct
FROM claims
GROUP BY service_month
ORDER BY service_month;


-- ── 7. PROVIDER PERFORMANCE ──

SELECT
    provider,
    department,
    COUNT(*)                                    AS total_claims,
    SUM(charge_amount)                          AS total_charges,
    SUM(payment_amount)                         AS total_collections,
    ROUND(AVG(CASE WHEN status='Denied' THEN 1.0 ELSE 0 END)*100, 2)
                                                AS denial_rate_pct,
    ROUND(AVG(NULLIF(days_in_ar,0)), 1)         AS avg_days_in_ar,
    -- Rank providers by denial rate within department
    RANK() OVER (PARTITION BY department ORDER BY AVG(CASE WHEN status='Denied' THEN 1.0 ELSE 0 END) DESC)
                                                AS denial_rank_in_dept
FROM claims
GROUP BY provider, department
ORDER BY denial_rate_pct DESC;


-- ── 8. APPEAL SUCCESS RATE ──

SELECT
    payer,
    denial_code,
    denial_reason,
    COUNT(*)                                            AS total_denials,
    SUM(CASE WHEN was_appealed THEN 1 ELSE 0 END)      AS appeals_filed,
    SUM(CASE WHEN was_appealed AND status='Appealed - Paid' THEN 1 ELSE 0 END)
                                                        AS appeals_won,
    ROUND(
        SUM(CASE WHEN was_appealed AND status='Appealed - Paid' THEN 1.0 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN was_appealed THEN 1 ELSE 0 END), 0) * 100
    , 2)                                                AS appeal_success_rate_pct,
    SUM(CASE WHEN was_appealed AND status='Appealed - Paid' THEN payment_amount ELSE 0 END)
                                                        AS revenue_recovered
FROM claims
WHERE status IN ('Denied', 'Appealed - Paid')
GROUP BY payer, denial_code, denial_reason
ORDER BY revenue_recovered DESC;


-- ── STORED PROCEDURE: Daily KPI Refresh ──────────────────────────────────────

CREATE OR REPLACE FUNCTION get_daily_kpi_snapshot()
RETURNS TABLE (
    metric_name     TEXT,
    metric_value    TEXT,
    benchmark       TEXT,
    status          TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH kpis AS (
        SELECT
            ROUND(AVG(CASE WHEN c.status='Denied' THEN 1.0 ELSE 0 END)*100, 2) AS denial_rate,
            ROUND(AVG(CASE WHEN c.status NOT IN ('Denied','Pending') AND c.was_appealed=FALSE THEN 1.0 ELSE 0 END)*100, 2) AS fprr,
            ROUND(AVG(NULLIF(c.days_in_ar,0)), 1) AS avg_ar,
            ROUND(SUM(c.payment_amount)/NULLIF(SUM(c.charge_amount),0)*100, 2) AS ncr
        FROM claims c
        WHERE c.service_date >= CURRENT_DATE - INTERVAL '30 days'
    )
    SELECT 'Denial Rate'::TEXT,             kpis.denial_rate || '%',   '< 10%',   CASE WHEN kpis.denial_rate < 10 THEN '✅ Good' ELSE '🔴 Needs Attention' END
    FROM kpis
    UNION ALL SELECT 'First Pass Resolution', kpis.fprr || '%',        '> 90%',   CASE WHEN kpis.fprr > 90 THEN '✅ Good' ELSE '🔴 Needs Attention' END FROM kpis
    UNION ALL SELECT 'Avg Days in AR',        kpis.avg_ar || ' days',  '< 40 days',CASE WHEN kpis.avg_ar < 40 THEN '✅ Good' ELSE '🔴 Needs Attention' END FROM kpis
    UNION ALL SELECT 'Net Collection Rate',   kpis.ncr || '%',         '> 95%',   CASE WHEN kpis.ncr > 95 THEN '✅ Good' ELSE '🔴 Needs Attention' END FROM kpis;
END;
$$ LANGUAGE plpgsql;

-- Run the KPI snapshot
SELECT * FROM get_daily_kpi_snapshot();
