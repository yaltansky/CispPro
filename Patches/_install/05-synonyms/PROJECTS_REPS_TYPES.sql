/****** Object:  Synonym [PROJECTS_REPS_TYPES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'PROJECTS_REPS_TYPES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [PROJECTS_REPS_TYPES] FOR [CISP_SHARED].[DBO].[PROJECTS_REPS_TYPES]
GO
