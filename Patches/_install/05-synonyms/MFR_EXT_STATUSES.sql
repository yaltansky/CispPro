/****** Object:  Synonym [MFR_EXT_STATUSES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'MFR_EXT_STATUSES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [MFR_EXT_STATUSES] FOR [CISP_SHARED].[DBO].[MFR_EXT_STATUSES]
GO
