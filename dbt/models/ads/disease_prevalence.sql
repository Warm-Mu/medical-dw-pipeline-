-- ============================================================
-- ADS: 疾病流行度分析
-- 业务用途:识别高发疾病,支撑医院资源规划和公共卫生决策
-- 分析维度:发病人数、流行率、平均发病年龄、性别分布
-- 说明:
--   1. prevalence_rate_pct = 该疾病累计诊断患者数 / 有效患者总数
--      属于"队列累计诊断覆盖率",不是时点患病率
--   2. avg_onset_age 基于每位患者的"首次诊断"计算,避免复诊拉偏
-- ============================================================

{{ config(materialized='table', tags=['ads']) }}

WITH valid_patients AS (
    -- 统一有效患者口径:排除占位 -1,并去重
    SELECT DISTINCT patient_sk
    FROM {{ ref('dim_patient') }}
    WHERE patient_sk != -1
),

-- 每位患者 × 每种疾病的首次诊断
patient_disease_first AS (
    SELECT
        f.patient_sk,
        d.description AS disease_name,
        d.code        AS disease_code,
        MIN(f.condition_start) AS first_diagnosed,
        MAX(f.condition_start) AS latest_diagnosed,
        COUNT(*)               AS total_diagnoses
    FROM {{ ref('fact_diagnosis') }} f
    JOIN {{ ref('dim_diagnosis') }} d
      ON f.diagnosis_sk_ref = d.diagnosis_sk
    JOIN valid_patients vp
      ON f.patient_sk = vp.patient_sk
    WHERE d.description LIKE '%(disorder)%'
    GROUP BY f.patient_sk, d.description, d.code
),

-- 按疾病聚合
disease_stats AS (
    SELECT
        pdf.disease_name,
        pdf.disease_code,
        COUNT(DISTINCT pdf.patient_sk) AS affected_patients,
        SUM(pdf.total_diagnoses)       AS total_diagnoses,
        ROUND(
            AVG(
                EXTRACT(YEAR FROM AGE(pdf.first_diagnosed, p.birth_date))
            )::numeric,
            1
        ) AS avg_onset_age,
        COUNT(DISTINCT CASE WHEN p.gender = 'M' THEN pdf.patient_sk END) AS male_count,
        COUNT(DISTINCT CASE WHEN p.gender = 'F' THEN pdf.patient_sk END) AS female_count,
        MIN(pdf.first_diagnosed) AS first_diagnosed,
        MAX(pdf.latest_diagnosed) AS latest_diagnosed
    FROM patient_disease_first pdf
    JOIN {{ ref('dim_patient') }} p
      ON pdf.patient_sk = p.patient_sk
    GROUP BY pdf.disease_name, pdf.disease_code
),

total_patients AS (
    SELECT COUNT(*) AS total_pop
    FROM valid_patients
)

SELECT
    RANK() OVER (ORDER BY affected_patients DESC) AS prevalence_rank,
    disease_name,
    disease_code,
    affected_patients,
    total_diagnoses,
    ROUND(
        100.0 * affected_patients / (SELECT total_pop FROM total_patients),
        2
    ) AS prevalence_rate_pct,
    avg_onset_age,
    male_count,
    female_count,
    CASE
        WHEN female_count = 0 THEN NULL
        ELSE ROUND(male_count::numeric / female_count, 2)
    END AS male_female_ratio,
    first_diagnosed,
    latest_diagnosed
FROM disease_stats
WHERE affected_patients >= 10   -- 过滤过于罕见的病(便于分析)
ORDER BY affected_patients DESC