/****** Object:  Synonym [MFR_R_PROVIDES_XSLICES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'MFR_R_PROVIDES_XSLICES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [MFR_R_PROVIDES_XSLICES] FOR [CISP_SHARED].[DBO].[MFR_R_PROVIDES_XSLICES]
GO
