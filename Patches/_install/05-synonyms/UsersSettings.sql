/****** Object:  Synonym [UsersSettings]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'UsersSettings' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [UsersSettings] FOR [CISP_SHARED]..[UsersSettings]
GO
