-- ============================================================
-- ADS: 患者生命周期价值(LTV)分析
-- 业务用途:识别高价值/流失患者,支撑医院精细化运营
-- 分层维度:LTV等级(S/A/B/C) × 活跃度(活跃/沉睡/流失)
-- ============================================================

{{ config(materialized='table', tags=['ads']) }}

WITH patient_activity AS (
    SELECT
        p.patient_sk,
        p.patient_id,
        p.gender,
        DATE_PART('year', AGE(NOW(), p.birth_date))::int AS current_age,
        COUNT(DISTINCT e.encounter_id) AS total_encounters,
        COUNT(DISTINCT DATE_TRUNC('year', e.encounter_start)) AS active_years,
        ROUND(SUM(e.total_claim_cost)::numeric, 2) AS lifetime_value,
        ROUND(AVG(e.total_claim_cost)::numeric, 2) AS avg_encounter_cost,
        MIN(e.encounter_start) AS first_visit,
        MAX(e.encounter_start) AS last_visit
    FROM {{ ref('dim_patient') }} p
    LEFT JOIN {{ ref('fact_encounter') }} e ON p.patient_sk = e.patient_sk
    WHERE p.death_date IS NULL  -- 只算在世患者
    GROUP BY p.patient_sk, p.patient_id, p.gender, p.birth_date
)
SELECT
    patient_id,
    gender,
    current_age,
    total_encounters,
    active_years,
    lifetime_value,
    avg_encounter_cost,
    first_visit,
    last_visit,
    -- 分层1:按LTV分成4档
    CASE
        WHEN lifetime_value >= 100000 THEN 'S级(超高价值)'
        WHEN lifetime_value >= 30000 THEN 'A级(高价值)'
        WHEN lifetime_value >= 10000 THEN 'B级(中价值)'
        ELSE 'C级(普通)'
    END AS ltv_tier,
    -- 分层2:活跃度(基于最近就诊时间)
    CASE
        WHEN last_visit >= NOW() - INTERVAL '1 year' THEN '活跃'
        WHEN last_visit >= NOW() - INTERVAL '2 years' THEN '沉睡'
        WHEN last_visit IS NULL THEN '未就诊'
        ELSE '流失'
    END AS activity_status
FROM patient_activity