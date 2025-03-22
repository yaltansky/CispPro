
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PLAN_PAYS_ROWS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PLAN_PAYS_ROWS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PLAN_PAY_ID] [int] NULL,
	[AGENT_ID] [int] NULL,
	[AGENT_NAME] [varchar](250) NULL,
	[CONSUMER_ID] [int] NULL,
	[CONSUMER_NAME] [varchar](250) NULL,
	[VENDOR_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[PAY_TYPE_ID] [int] NULL,
	[PROBABILITY] [decimal](5, 2) NULL,
	[VALUE_PLAN] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

