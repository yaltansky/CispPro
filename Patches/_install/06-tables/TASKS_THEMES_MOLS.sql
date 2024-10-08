/****** Object:  Table [TASKS_THEMES_MOLS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TASKS_THEMES_MOLS]') AND type in (N'U'))
BEGIN
CREATE TABLE [TASKS_THEMES_MOLS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[THEME_ID] [int] NOT NULL,
	[MOL_ID] [int] NOT NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ROLE_ID] [int] NOT NULL DEFAULT ((20)),
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_TASKS_THEMES_MOLS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[TASKS_THEMES_MOLS]') AND name = N'IX_TASKS_THEMES_MOLS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_TASKS_THEMES_MOLS] ON [TASKS_THEMES_MOLS]
(
	[THEME_ID] ASC,
	[ROLE_ID] ASC,
	[MOL_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
