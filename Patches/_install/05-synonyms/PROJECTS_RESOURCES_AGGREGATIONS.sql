/****** Object:  Synonym [PROJECTS_RESOURCES_AGGREGATIONS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'PROJECTS_RESOURCES_AGGREGATIONS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [PROJECTS_RESOURCES_AGGREGATIONS] FOR [CISP_SHARED].[DBO].[PROJECTS_RESOURCES_AGGREGATIONS]
GO
