IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'UsersRoles' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [UsersRoles] FOR [CISP_SHARED]..[UsersRoles]
GO
