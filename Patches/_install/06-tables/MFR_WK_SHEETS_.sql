/****** Object:  Table [MFR_WK_SHEETS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_WK_SHEETS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_WK_SHEETS](
	[WK_SHEET_ID] [int] IDENTITY(1,1) NOT NULL,
	[SUBJECT_ID] [int] NULL,
	[AGENT_ID] [int] NULL,
	[PLACE_ID] [int] NULL,
	[STATUS_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[NUMBER] [varchar](50) NULL,
	[NOTE] [varchar](max) NULL,
	[EXECUTOR_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[EXTERN_ID] [varchar](50) NULL,
	[WK_SHIFT] [varchar](10) NULL,
PRIMARY KEY CLUSTERED 
(
	[WK_SHEET_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO
/****** Object:  Index [IX_MFR_WK_SHEETS_EXTERN]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_WK_SHEETS]') AND name = N'IX_MFR_WK_SHEETS_EXTERN')
CREATE NONCLUSTERED INDEX [IX_MFR_WK_SHEETS_EXTERN] ON [MFR_WK_SHEETS]
(
	[EXTERN_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
