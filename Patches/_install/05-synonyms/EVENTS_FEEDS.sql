/****** Object:  Synonym [EVENTS_FEEDS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'EVENTS_FEEDS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [EVENTS_FEEDS] FOR [CISP_SHARED].[DBO].[EVENTS_FEEDS]
GO
