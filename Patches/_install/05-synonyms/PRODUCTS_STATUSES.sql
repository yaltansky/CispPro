/****** Object:  Synonym [PRODUCTS_STATUSES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'PRODUCTS_STATUSES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [PRODUCTS_STATUSES] FOR [CISP_SHARED].[DBO].[PRODUCTS_STATUSES]
GO
