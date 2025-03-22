IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[RolesObjects]') AND type in (N'U'))
BEGIN
CREATE TABLE [RolesObjects](
	[ObjectId] [int] NOT NULL,
	[RoleId] [int] NOT NULL,
	[MolId] [int] NOT NULL,
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[ObjectType] [varchar](3) NULL,
	[ObjectName] [varchar](255) NULL,
 CONSTRAINT [PK_RolesObjects] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)
)
END
GO
