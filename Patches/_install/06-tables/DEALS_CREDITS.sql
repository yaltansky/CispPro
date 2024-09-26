/****** Object:  Table [DEALS_CREDITS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_CREDITS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_CREDITS](
	[SUBJECT_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[MOVE_TYPE_ID] [int] NULL,
	[FINDOC_ID] [int] NULL,
	[BUDGET_ID] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[VALUE] [decimal](18, 2) NULL
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_DEALS_CREDITS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DEALS_CREDITS]') AND name = N'IX_DEALS_CREDITS')
CREATE CLUSTERED INDEX [IX_DEALS_CREDITS] ON [DEALS_CREDITS]
(
	[SUBJECT_ID] ASC,
	[BUDGET_ID] ASC,
	[ARTICLE_ID] ASC,
	[D_DOC] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_DEALS_CREDITS2]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DEALS_CREDITS]') AND name = N'IX_DEALS_CREDITS2')
CREATE NONCLUSTERED INDEX [IX_DEALS_CREDITS2] ON [DEALS_CREDITS]
(
	[SUBJECT_ID] ASC,
	[MOVE_TYPE_ID] ASC,
	[D_DOC] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
