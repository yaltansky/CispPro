/****** Object:  Synonym [APP_DATABASES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'APP_DATABASES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [APP_DATABASES] FOR [CISP_SHARED]..[APP_DATABASES]
GO
