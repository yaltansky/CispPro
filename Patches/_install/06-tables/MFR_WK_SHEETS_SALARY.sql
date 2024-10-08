/****** Object:  Table [MFR_WK_SHEETS_SALARY]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_WK_SHEETS_SALARY]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_WK_SHEETS_SALARY](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[WK_SHEET_ID] [int] NULL,
	[WK_DETAIL_ID] [int] NULL,
	[D_DOC] [date] NULL,
	[PARENT_MOL_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[POST_ID] [int] NULL,
	[WK_HOURS] [float] NULL,
	[WK_SHIFT] [varchar](20) NULL,
	[KTU] [float] NULL DEFAULT ((1)),
	[K_INC] [float] NULL DEFAULT ((1)),
	[SALARY_BASE] [decimal](18, 2) NULL,
	[SALARY] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[HAS_CHILDS] [bit] NULL,
	[KTD] [float] NULL DEFAULT ((0)),
	[WK_COMPLETION] [float] NULL,
	[SALARY_AWARD] [decimal](18, 2) NULL,
	[PERIOD_FROM] [date] NULL,
	[PERIOD_TO] [date] NULL,
	[WK_HOURS_PERIOD] [float] NULL,
	[WK_COMPLETION_PERIOD] [float] NULL,
	[KTD_PERIOD] [float] NULL DEFAULT ((0)),
	[SALARY_BASE_PERIOD] [decimal](18, 2) NULL,
	[SALARY_AWARD_PERIOD] [decimal](18, 2) NULL,
	[SALARY_PERIOD] [decimal](18, 2) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_CALC]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_WK_SHEETS_SALARY]') AND name = N'IX_CALC')
CREATE NONCLUSTERED INDEX [IX_CALC] ON [MFR_WK_SHEETS_SALARY]
(
	[D_DOC] ASC,
	[MOL_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_JOIN]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_WK_SHEETS_SALARY]') AND name = N'IX_JOIN')
CREATE NONCLUSTERED INDEX [IX_JOIN] ON [MFR_WK_SHEETS_SALARY]
(
	[WK_SHEET_ID] ASC,
	[MOL_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MFR_WK_SHEETS_SALARY_SHEET_ID]') AND parent_object_id = OBJECT_ID(N'[MFR_WK_SHEETS_SALARY]'))
ALTER TABLE [MFR_WK_SHEETS_SALARY]  WITH CHECK ADD  CONSTRAINT [FK_MFR_WK_SHEETS_SALARY_SHEET_ID] FOREIGN KEY([WK_SHEET_ID])
REFERENCES [MFR_WK_SHEETS] ([WK_SHEET_ID])
ON DELETE CASCADE
GO
IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MFR_WK_SHEETS_SALARY_SHEET_ID]') AND parent_object_id = OBJECT_ID(N'[MFR_WK_SHEETS_SALARY]'))
ALTER TABLE [MFR_WK_SHEETS_SALARY] CHECK CONSTRAINT [FK_MFR_WK_SHEETS_SALARY_SHEET_ID]
GO
