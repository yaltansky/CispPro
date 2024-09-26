/****** Object:  Table [MFR_PDM_OPERS_RESOURCES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_PDM_OPERS_RESOURCES]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_PDM_OPERS_RESOURCES](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[PDM_ID] [int] NULL,
	[OPER_ID] [int] NULL,
	[RESOURCE_ID] [int] NULL,
	[LOADING] [float] NULL,
	[LOADING_PRICE] [float] NULL,
	[LOADING_VALUE] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NULL,
PRIMARY KEY NONCLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_MFR_PDM_OPERS_RESOURCES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PDM_OPERS_RESOURCES]') AND name = N'IX_MFR_PDM_OPERS_RESOURCES')
CREATE CLUSTERED INDEX [IX_MFR_PDM_OPERS_RESOURCES] ON [MFR_PDM_OPERS_RESOURCES]
(
	[PDM_ID] ASC,
	[OPER_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
