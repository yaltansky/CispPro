/****** Object:  Synonym [MFR_PLANS_JOBS_TYPES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'MFR_PLANS_JOBS_TYPES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [MFR_PLANS_JOBS_TYPES] FOR [CISP_SHARED].[DBO].[MFR_PLANS_JOBS_TYPES]
GO
