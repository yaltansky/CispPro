/****** Object:  Synonym [CCY]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'CCY' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [CCY] FOR [CISP_SHARED].[DBO].[CCY]
GO
