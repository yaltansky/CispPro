/****** Object:  Synonym [OPTIONS_LISTS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'OPTIONS_LISTS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [OPTIONS_LISTS] FOR [CISP_SHARED].[DBO].[OPTIONS_LISTS]
GO
