/****** Object:  View [AGENTS_REFS]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[AGENTS_REFS]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [AGENTS_REFS] AS SELECT PARENT_COMPANY_ID, AGENT_ID, NAME, INN FROM AGENTS
' 
GO
