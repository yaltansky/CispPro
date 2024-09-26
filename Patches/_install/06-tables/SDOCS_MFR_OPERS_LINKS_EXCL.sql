/****** Object:  Table [SDOCS_MFR_OPERS_LINKS_EXCL]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_OPERS_LINKS_EXCL]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_MFR_OPERS_LINKS_EXCL](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[MFR_DOC_ID] [int] NULL,
	[PRODUCT_ID] [int] NULL,
	[ITEM_ID] [int] NULL,
	[OPER_NUMBER] [int] NULL,
	[IN_ITEM_ID] [int] NULL,
	[IN_OPER_NUMBER] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_SDOCS_MFR_OPERS_LINKS_EXCL]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_OPERS_LINKS_EXCL]') AND name = N'IX_SDOCS_MFR_OPERS_LINKS_EXCL')
CREATE NONCLUSTERED INDEX [IX_SDOCS_MFR_OPERS_LINKS_EXCL] ON [SDOCS_MFR_OPERS_LINKS_EXCL]
(
	[MFR_DOC_ID] ASC,
	[PRODUCT_ID] ASC,
	[ITEM_ID] ASC,
	[IN_ITEM_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
