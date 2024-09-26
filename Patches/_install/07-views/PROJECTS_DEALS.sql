﻿IF OBJECT_ID('PROJECTS_DEALS') IS NOT NULL DROP VIEW PROJECTS_DEALS
GO
CREATE VIEW PROJECTS_DEALS 
WITH SCHEMABINDING
AS 
SELECT
	P.TYPE_ID,
	P.PARENT_ID,
	D.DEAL_ID, 
	P.TEMPLATE_ID,
	P.BUDGET_TYPE_ID,
	D.STATUS_ID,
	P.NAME,
	P.CURATOR_ID, P.ADMIN_ID, P.CHIEF_ID, 
	D.D_DOC,
	--
	D.SUBJECT_ID, 
	D.VENDOR_ID, 
	D.CCY_ID, 
	D.VALUE_CCY, 
	D.CUSTOMER_ID AS AGENT_ID,
	D.NUMBER,
	D.NOTE,
	D.CONTENT
FROM dbo.DEALS D
	JOIN dbo.PROJECTS P ON P.PROJECT_ID = D.DEAL_ID
WHERE P.TYPE_ID = 3

GO

CREATE UNIQUE CLUSTERED INDEX IDX_PROJECTS_DEALS ON PROJECTS_DEALS (DEAL_ID)
GO
