/****** Object:  Synonym [PERIODS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'PERIODS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [PERIODS] FOR [CISP_SHARED].[DBO].[PERIODS]
GO
