/****** Object:  Synonym [WEEKS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'WEEKS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [WEEKS] FOR [CISP_SHARED].[DBO].[WEEKS]
GO
