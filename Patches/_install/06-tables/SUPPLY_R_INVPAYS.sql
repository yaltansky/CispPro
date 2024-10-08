/****** Object:  Table [SUPPLY_R_INVPAYS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SUPPLY_R_INVPAYS]') AND type in (N'U'))
BEGIN
CREATE TABLE [SUPPLY_R_INVPAYS](
	[ROW_ID] [int] IDENTITY(1,1) NOT NULL,
	[ACC_REGISTER_ID] [int] NULL,
	[PLAN_ID] [int] NULL,
	[MFR_DOC_ID] [int] NOT NULL,
	[PRODUCT_ID] [int] NULL,
	[ITEM_ID] [int] NOT NULL,
	[INV_ID] [int] NULL,
	[INV_CONDITION] [varchar](20) NULL,
	[INV_CONDITION_PAY] [varchar](20) NULL,
	[INV_CONDITION_FUND] [varchar](20) NULL,
	[INV_DATE] [date] NULL,
	[INV_D_PLAN] [date] NULL,
	[INV_D_CONDITION] [date] NULL,
	[INV_MILESTONE_ID] [int] NULL,
	[INV_MS_D_PLAN] [date] NULL,
	[INV_MS_D_FACT] [date] NULL,
	[INV_D_MFR] [date] NULL,
	[INV_D_MFR_TO] [date] NULL,
	[INV_VALUE] [float] NULL,
	[INV_FUND_VALUE] [float] NULL,
	[INV_Q] [float] NULL,
	[INV_Q_SHIP] [float] NULL,
	[FINDOC_ID] [int] NULL,
	[FINDOC_DATE] [date] NULL,
	[FINDOC_VALUE] [float] NULL,
	[SLICE] [varchar](16) NULL,
	[NOTE] [varchar](50) NULL,
	[D_CALC] [datetime] NULL DEFAULT (getdate()),
PRIMARY KEY CLUSTERED 
(
	[ROW_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

/****** Object:  Index [IX_SUPPLY_R_INVPAYS1]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SUPPLY_R_INVPAYS]') AND name = N'IX_SUPPLY_R_INVPAYS1')
CREATE NONCLUSTERED INDEX [IX_SUPPLY_R_INVPAYS1] ON [SUPPLY_R_INVPAYS]
(
	[MFR_DOC_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_SUPPLY_R_INVPAYS2]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SUPPLY_R_INVPAYS]') AND name = N'IX_SUPPLY_R_INVPAYS2')
CREATE NONCLUSTERED INDEX [IX_SUPPLY_R_INVPAYS2] ON [SUPPLY_R_INVPAYS]
(
	[MFR_DOC_ID] ASC,
	[ITEM_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_SUPPLY_R_INVPAYS3]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SUPPLY_R_INVPAYS]') AND name = N'IX_SUPPLY_R_INVPAYS3')
CREATE NONCLUSTERED INDEX [IX_SUPPLY_R_INVPAYS3] ON [SUPPLY_R_INVPAYS]
(
	[INV_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_SUPPLY_R_INVPAYS4]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SUPPLY_R_INVPAYS]') AND name = N'IX_SUPPLY_R_INVPAYS4')
CREATE NONCLUSTERED INDEX [IX_SUPPLY_R_INVPAYS4] ON [SUPPLY_R_INVPAYS]
(
	[INV_ID] ASC,
	[INV_MILESTONE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_SUPPLY_R_INVPAYS5]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SUPPLY_R_INVPAYS]') AND name = N'IX_SUPPLY_R_INVPAYS5')
CREATE NONCLUSTERED INDEX [IX_SUPPLY_R_INVPAYS5] ON [SUPPLY_R_INVPAYS]
(
	[PLAN_ID] ASC,
	[INV_ID] ASC,
	[MFR_DOC_ID] ASC,
	[ITEM_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
