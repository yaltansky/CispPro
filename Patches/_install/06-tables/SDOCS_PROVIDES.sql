/****** Object:  Table [SDOCS_PROVIDES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_PROVIDES]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_PROVIDES](
	[ROW_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NULL,
	[STOCK_ID] [int] NOT NULL,
	[PRODUCT_ID] [int] NOT NULL,
	[AGENT_ID] [int] NULL,
	[ID_MFR] [int] NULL,
	[ID_ISSUE] [int] NULL,
	[ID_SHIP] [int] NULL,
	[ID_ORDER] [int] NULL,
	[ID_DEAL] [int] NULL,
	[D_MFR] [datetime] NULL,
	[D_ISSUE_PLAN] [datetime] NULL,
	[D_ISSUE] [datetime] NULL,
	[D_SHIP] [datetime] NULL,
	[D_ORDER] [datetime] NULL,
	[D_DELIVERY] [datetime] NULL,
	[Q_MFR] [decimal](18, 2) NULL,
	[Q_ISSUE] [decimal](18, 2) NULL,
	[Q_SHIP] [decimal](18, 2) NULL,
	[Q_ORDER] [decimal](18, 2) NULL,
	[V_MFR] [decimal](18, 2) NULL,
	[V_ORDER] [decimal](18, 2) NULL,
	[V_PAID] [decimal](18, 2) NULL,
	[SLICE] [varchar](16) NULL,
	[NOTE] [varchar](500) NULL,
	[D_CALC] [datetime] NULL DEFAULT (getdate()),
PRIMARY KEY CLUSTERED 
(
	[ROW_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

/****** Object:  Index [IX_SDOCS_PROVIDES_ORDER]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_PROVIDES]') AND name = N'IX_SDOCS_PROVIDES_ORDER')
CREATE NONCLUSTERED INDEX [IX_SDOCS_PROVIDES_ORDER] ON [SDOCS_PROVIDES]
(
	[ID_ORDER] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
