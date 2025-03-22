IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[Roles]') AND type in (N'U'))
BEGIN
CREATE TABLE [Roles](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[Name] [varchar](64) NOT NULL,
	[Description] [varchar](255) NULL,
	[AddDate] [datetime] NULL DEFAULT (getdate()),
    PRIMARY KEY CLUSTERED 
    (
        [Id] ASC
    )
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[Roles]') AND name = N'ix_Roles')
CREATE UNIQUE NONCLUSTERED INDEX [ix_Roles] ON [Roles]
(
	[Name] ASC
)
GO
