/****** Object:  Synonym [UsersLogs]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'UsersLogs' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [UsersLogs] FOR [CISP_SHARED]..[UsersLogs]
GO
