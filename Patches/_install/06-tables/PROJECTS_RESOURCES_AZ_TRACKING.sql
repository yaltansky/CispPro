/****** Object:  Table [PROJECTS_RESOURCES_AZ_TRACKING]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_RESOURCES_AZ_TRACKING]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_RESOURCES_AZ_TRACKING](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[MOL_ID] [int] NOT NULL,
	[TREE_ID] [int] NULL,
	[TASK_ID] [int] NULL,
	[D_FROM] [datetime] NULL,
	[D_AFTER] [datetime] NULL,
	[REBATE_SHIFT] [int] NULL,
	[IS_MANUAL] [bit] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_PROJECTS_RESOURCES_AZ_TRACKING]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PROJECTS_RESOURCES_AZ_TRACKING]') AND name = N'IX_PROJECTS_RESOURCES_AZ_TRACKING')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PROJECTS_RESOURCES_AZ_TRACKING] ON [PROJECTS_RESOURCES_AZ_TRACKING]
(
	[TREE_ID] ASC,
	[TASK_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
