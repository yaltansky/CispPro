/****** Object:  Synonym [QUEUES_OBJS]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'QUEUES_OBJS' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [QUEUES_OBJS] FOR [CISP_SHARED]..[QUEUES_OBJS]
GO
