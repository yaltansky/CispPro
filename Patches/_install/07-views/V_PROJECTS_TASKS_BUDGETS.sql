﻿IF OBJECT_ID('V_PROJECTS_TASKS_BUDGETS') IS NOT NULL
	DROP VIEW V_PROJECTS_TASKS_BUDGETS
GO

CREATE VIEW V_PROJECTS_TASKS_BUDGETS
AS

SELECT 
	B.ID,
	DETAIL_ID = D.ID,
	B.PROJECT_ID, B.BUDGET_ID, B.TASK_ID, B.ARTICLE_ID,
	D_DOC = ISNULL(D.D_DOC, B.D_DOC),
	D_DOC_CALC = ISNULL(D.D_DOC_CALC, B.D_DOC_CALC), 
	DATE_TYPE_ID = ISNULL(D.DATE_TYPE_ID, B.DATE_TYPE_ID),
	DATE_LAG = ISNULL(D.DATE_LAG, B.DATE_LAG),
	BUDGET_PERIOD_ID = ISNULL(D.BUDGET_PERIOD_ID, B.BUDGET_PERIOD_ID), 
	PLAN_BDR = CASE WHEN D.ID IS NULL then B.PLAN_BDR ELSE D.PLAN_BDR END, 
	PLAN_DDS = CASE WHEN D.ID IS NULL then B.PLAN_DDS ELSE D.PLAN_DDS END, 
	FACT_DDS = CASE WHEN D.ID IS NULL then B.FACT_DDS ELSE D.FACT_DDS END, 
	NOTE = ISNULL(D.NOTE, B.NOTE),
	HAS_DETAILS = CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END
FROM PROJECTS_TASKS_BUDGETS B
	LEFT JOIN PROJECTS_TASKS_BUDGETS_DETAILS D ON D.PARENT_ID = B.ID

GO
