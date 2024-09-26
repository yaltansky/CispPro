/****** Object:  Table [DEALS_R_WORK_CAPITAL]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_R_WORK_CAPITAL]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_R_WORK_CAPITAL](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DEAL_ID] [int] NULL,
	[DEAL_NUMBER] [varchar](50) NULL,
	[AGENT_NAME] [varchar](150) NULL,
	[PAY_CONDITIONS] [varchar](50) NULL,
	[MFR_NUMBER] [varchar](50) NULL,
	[VENDOR_NAME] [varchar](150) NULL,
	[DIRECTION_NAME] [varchar](100) NULL,
	[MOL_NAME] [varchar](50) NULL,
	[ARTICLE_GROUP_NAME] [varchar](150) NULL,
	[PLAN_PAY_NAME] [varchar](50) NULL,
	[D_PLAN_PAY] [datetime] NULL,
	[D_FACT_PAY] [datetime] NULL,
	[GROUP1_NAME] [varchar](50) NULL,
	[GROUP2_NAME] [varchar](50) NULL,
	[STATUS_NAME] [varchar](30) NULL,
	[VALUE_PLAN] [decimal](18, 2) NULL,
	[VALUE_FACT] [decimal](18, 2) NULL,
	[VALUE_FUND] [decimal](18, 2) NULL,
	[VALUE_PLAN_PAY] [decimal](18, 2) NULL,
	[D_CALC] [datetime] NULL DEFAULT (getdate()),
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

/****** Object:  Index [IX_DEAL]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DEALS_R_WORK_CAPITAL]') AND name = N'IX_DEAL')
CREATE NONCLUSTERED INDEX [IX_DEAL] ON [DEALS_R_WORK_CAPITAL]
(
	[DEAL_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_DEALS_R_WORK_CAPITAL]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DEALS_R_WORK_CAPITAL]') AND name = N'IX_DEALS_R_WORK_CAPITAL')
CREATE NONCLUSTERED INDEX [IX_DEALS_R_WORK_CAPITAL] ON [DEALS_R_WORK_CAPITAL]
(
	[MFR_NUMBER] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
