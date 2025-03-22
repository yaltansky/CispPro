USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[UsersRoles]') AND type in (N'U'))
BEGIN
CREATE TABLE [UsersRoles](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[RoleId] [int] NOT NULL,
	[UserId] [int] NOT NULL,
	[AddDate] [datetime] NULL DEFAULT (getdate()),
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)
)
END
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[UsersRoles]') AND name = N'IX_UsersRoles')
CREATE UNIQUE NONCLUSTERED INDEX [IX_UsersRoles] ON [UsersRoles]
(
	[RoleId] ASC,
	[UserId] ASC
)
GO
