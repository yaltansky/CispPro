/****** Object:  Synonym [QUEUES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'QUEUES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [QUEUES] FOR [CISP_SHARED]..[QUEUES]
GO
