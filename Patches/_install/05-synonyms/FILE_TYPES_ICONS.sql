/****** Object:  Synonym [FILE_TYPES_ICONS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'FILE_TYPES_ICONS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [FILE_TYPES_ICONS] FOR [CISP_SHARED].[DBO].[FILE_TYPES_ICONS]
GO
