/****** Object:  Synonym [COUNTRIES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'COUNTRIES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [COUNTRIES] FOR [CISP_SHARED].[DBO].[COUNTRIES]
GO
