﻿IF OBJECT_ID('DEALS_DOCS_DOGOVORS') IS NOT NULL DROP VIEW DEALS_DOCS_DOGOVORS
GO

CREATE VIEW DEALS_DOCS_DOGOVORS
WITH SCHEMABINDING
AS 
SELECT DOC_ID, D_DOC, NUMBER, EXTERNAL_ID
FROM DBO.DEALS_DOCS
WHERE TYPE_ID = 1

GO

CREATE UNIQUE CLUSTERED INDEX IDX_DEALS_DOCS_DOGOVORS ON DEALS_DOCS_DOGOVORS(DOC_ID)
GO
