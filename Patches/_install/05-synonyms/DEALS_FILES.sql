/****** Object:  Synonym [DEALS_FILES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'DEALS_FILES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [DEALS_FILES] FOR [CISP_FILES].[DBO].[DEALS_FILES]
GO
