/****** Object:  Synonym [CCY_RATES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'CCY_RATES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [CCY_RATES] FOR [CISP_SHARED].[DBO].[CCY_RATES]
GO
