/****** Object:  Synonym [TASKS_STATUSES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'TASKS_STATUSES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [TASKS_STATUSES] FOR [CISP_SHARED].[DBO].[TASKS_STATUSES]
GO
