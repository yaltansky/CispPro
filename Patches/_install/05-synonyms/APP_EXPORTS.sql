/****** Object:  Synonym [APP_EXPORTS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'APP_EXPORTS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [APP_EXPORTS] FOR [CISP_GATE]..[APP_EXPORTS]
GO
