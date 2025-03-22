
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[R_DEALS_WORK_CAPITAL]') AND type in (N'U'))
BEGIN
CREATE TABLE [R_DEALS_WORK_CAPITAL](
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
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[R_DEALS_WORK_CAPITAL]') AND name = N'IX_DEAL')
CREATE NONCLUSTERED INDEX [IX_DEAL] ON [R_DEALS_WORK_CAPITAL]
(
	[DEAL_ID] ASC
)
GO
