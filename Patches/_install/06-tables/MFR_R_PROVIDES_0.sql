/****** Object:  Table [MFR_R_PROVIDES_0]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_R_PROVIDES_0]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_R_PROVIDES_0](
	[MFR_DOC_ID] [int] NOT NULL,
	[ITEM_ID] [int] NOT NULL,
	[UNIT_NAME] [varchar](20) NULL,
	[AGENT_ID] [int] NULL,
	[ID_MFR] [int] NULL,
	[ID_ORDER] [int] NULL,
	[ID_INVOICE] [int] NULL,
	[ID_SHIP] [int] NULL,
	[ID_JOB] [int] NULL,
	[D_MFR] [date] NULL,
	[D_MFR_TO] [date] NULL,
	[D_ORDER] [date] NULL,
	[D_INVOICE] [date] NULL,
	[D_DELIVERY] [date] NULL,
	[D_SHIP] [date] NULL,
	[D_JOB] [date] NULL,
	[Q_MFR] [float] NULL,
	[Q_ORDER] [float] NULL,
	[Q_INVOICE] [float] NULL,
	[Q_SHIP] [float] NULL,
	[Q_JOB] [float] NULL,
	[PRICE_INVOICE] [float] NULL,
	[SLICE] [varchar](16) NULL,
	[NOTE] [varchar](100) NULL,
	[D_CALC] [datetime] not null DEFAULT getdate()
) ON [PRIMARY]
END
GO
