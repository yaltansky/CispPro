USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[UsersSettings]') AND type in (N'U'))
BEGIN
CREATE TABLE [UsersSettings](
	[Id] [varchar](100) NOT NULL,
	[UserId] [int] NULL,
	[GroupId] [varchar](50) NULL,
	[Settings] [varchar](max) NULL,
 CONSTRAINT [PK_UsersSettings] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)
)
END
GO
SET ANSI_PADDING ON

GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[UsersSettings]') AND name = N'IX_UsersSettings')
CREATE UNIQUE NONCLUSTERED INDEX [IX_UsersSettings] ON [UsersSettings]
(
	[UserId] ASC,
	[GroupId] ASC,
	[Id] ASC
)
GO
