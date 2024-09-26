/****** Object:  Table [PROJECTS_FAVORITES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_FAVORITES]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_FAVORITES](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[MOL_ID] [int] NOT NULL,
	[PROJECT_ID] [int] NOT NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_PROJECTS_FAVORITES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PROJECTS_FAVORITES]') AND name = N'IX_PROJECTS_FAVORITES')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PROJECTS_FAVORITES] ON [PROJECTS_FAVORITES]
(
	[MOL_ID] ASC,
	[PROJECT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
