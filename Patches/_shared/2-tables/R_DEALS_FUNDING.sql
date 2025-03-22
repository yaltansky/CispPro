
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[R_DEALS_FUNDING]') AND type in (N'U'))
BEGIN
CREATE TABLE [R_DEALS_FUNDING](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DEAL_ID] [int] NULL,
	[STATUS_NAME] [varchar](50) NULL,
	[MFR_NUMBER] [varchar](50) NULL,
	[ARTICLE_ID] [int] NULL,
	[FUND_PAYORDER_ID] [int] NULL,
	[PLAN_PAY_NAME] [varchar](50) NULL,
	[D_MFR] [datetime] NULL,
	[D_ISSUE] [datetime] NULL,
	[D_ISSUE_PLAN] [datetime] NULL,
	[D_SHIP] [datetime] NULL,
	[D_ORDER] [datetime] NULL,
	[D_DELIVERY] [datetime] NULL,
	[D_PLAN_PAY] [datetime] NULL,
	[D_FACT_PAY] [datetime] NULL,
	[D_FUND] [datetime] NULL,
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


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[R_DEALS_FUNDING]') AND name = N'IX_DEAL')
CREATE NONCLUSTERED INDEX [IX_DEAL] ON [R_DEALS_FUNDING]
(
	[DEAL_ID] ASC
)
GO
