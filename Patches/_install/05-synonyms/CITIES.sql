/****** Object:  Synonym [CITIES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'CITIES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [CITIES] FOR [CISP_SHARED].[DBO].[CITIES]
GO
