﻿IF OBJECT_ID('DEALS_DOCS_PRINCIPALS') IS NOT NULL DROP VIEW DEALS_DOCS_PRINCIPALS
GO

CREATE VIEW DEALS_DOCS_PRINCIPALS
WITH SCHEMABINDING
AS 
SELECT DOCUMENT_ID, NAME = NUMBER, D_DOC, NUMBER, EXTERNAL_ID
FROM DBO.DOCUMENTS
WHERE CHARINDEX('ДОГОВОР С ПРИНЦИПАЛОМ', TAGS, 1) > 0

GO

CREATE UNIQUE CLUSTERED INDEX IDX_DEALS_DOCS_PRINCIPALS ON DEALS_DOCS_PRINCIPALS(DOCUMENT_ID)
GO
