-- ============================================================
-- 业务测试:用药结束日期不能早于开始日期
-- 
-- 业务背景:医生开药时,STOP(停药日期)必须晚于或等于START(开始日期)
-- 违反规则意味着:数据录入错误、时区问题、或ETL转换逻辑bug
-- 
-- dbt测试规约:
--   - 查询返回0行 = 测试通过
--   - 查询返回>0行 = 测试失败,输出违规记录
-- ============================================================
{{ config(severity='warn') }}
SELECT
    medication_id,
    patient_sk,
    encounter_sk,
    start_date,
    stop_date,
    stop_date - start_date::date AS days_diff
FROM {{ ref('fact_medication') }}
WHERE stop_date IS NOT NULL
  AND stop_date < start_date