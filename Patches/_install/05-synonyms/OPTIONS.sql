/****** Object:  Synonym [OPTIONS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'OPTIONS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [OPTIONS] FOR [CISP_SHARED].[DBO].[OPTIONS]
GO
