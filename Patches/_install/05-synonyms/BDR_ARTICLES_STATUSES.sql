/****** Object:  Synonym [BDR_ARTICLES_STATUSES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'BDR_ARTICLES_STATUSES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [BDR_ARTICLES_STATUSES] FOR [CISP_SHARED].[DBO].[BDR_ARTICLES_STATUSES]
GO
