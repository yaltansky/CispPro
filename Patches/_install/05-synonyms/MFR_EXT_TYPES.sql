/****** Object:  Synonym [MFR_EXT_TYPES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'MFR_EXT_TYPES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [MFR_EXT_TYPES] FOR [CISP_SHARED].[DBO].[MFR_EXT_TYPES]
GO
