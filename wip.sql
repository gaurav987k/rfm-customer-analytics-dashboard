CREATE OR REPLACE TABLE `rfm-analysis-495207.sales.sales_2025` AS

SELECT * FROM `rfm-analysis-495207.sales.2025-1`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-2`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-3`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-4`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-5`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-6`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-7`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-8`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-9`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-10`
UNION ALL
SELECT * FROM `rfm-analysis-495207.sales.2025-11`
UNION ALL
SELECT * EXCEPT(string_field_5, string_field_6, string_field_7)
FROM `rfm-analysis-495207.sales.2025-12`;

----------------------------
--STEP 2 CALCULATE FREQUENCY,RECENY,MONETARY R FM RANKS 
--COMBINE VIEWS WITH CTES
CREATE OR REPLACE view `rfm-analysis-495207.sales.rfmmetrics`

AS
WITH  current_date as 
(
  select date('2026-03-06') as analysis_date --today date

),
rfm as
(
  select
  CustomerID,
  MAX(OrderDate) as last_order_date,
  date_diff((select analysis_date from current_date),MAX (OrderDate),DAY) as receny,
  COunt(*) As frequency,
  SUM(OrderValue) AS monetary
FRom `rfm-analysis-495207.sales.sales_2025`
group by CustomerID
)

select 
 rfm.*,
 row_number() over(order by receny asc) as r_rank,
 row_number() over(order by frequency desc) as f_rank,
 row_number() over(order by monetary desc) as m_rank
from rfm;



---------step #: assign deciles ( 10=best , 1= worst)

create or replace view `rfm-analysis-495207.sales.rfmscores`
as 
select * ,
ntile(10) over(order by r_rank desc) as r_score,
ntile(10) over(order by f_rank desc) as f_score,
ntile(10) over(order by m_rank desc) as m_score



from `rfm-analysis-495207.sales.rfmmetrics`;

-----step 4 total score 

CREATE OR REPLACE VIEW `rfm-analysis-495207.sales.rfm_totalscores` AS

select 
  CustomerID,
  receny,
  frequency,
  monetary,
  r_score,
  f_score,
  m_score,
  (r_score + f_score + m_score) as rfm_total_score
from `rfm-analysis-495207.sales.rfmscores`
order by rfm_total_score desc;


----step 5 bi ready table ------
CREATE OR REPLACE VIEW `rfm-analysis-495207.sales.rfm_segments` AS

SELECT
    CustomerID,
    receny,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    rfm_total_score,

CASE

    WHEN rfm_total_score BETWEEN 25 AND 30
    THEN 'Champions'

    WHEN rfm_total_score BETWEEN 20 AND 24
    THEN 'Loyal Customers'

    WHEN rfm_total_score BETWEEN 15 AND 19
    THEN 'Potential Loyalists'

    WHEN rfm_total_score BETWEEN 10 AND 14
    THEN 'At Risk'

    WHEN rfm_total_score BETWEEN 5 AND 9
    THEN 'Hibernating'

    ELSE 'Lost Customers'

END AS customer_segment

FROM `rfm-analysis-495207.sales.rfm_totalscores`

ORDER BY rfm_total_score DESC;