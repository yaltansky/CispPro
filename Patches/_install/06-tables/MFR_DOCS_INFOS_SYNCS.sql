/****** Object:  Table [MFR_DOCS_INFOS_SYNCS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_DOCS_INFOS_SYNCS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_DOCS_INFOS_SYNCS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[INFO_ID] [int] NULL,
	[MFR_DOC_ID] [int] NULL,
	[CONTENT_ID] [int] NULL,
	[NAME] [varchar](500) NULL,
	[DELAY] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

/****** Object:  Index [IX_MFR_DOCS_INFOS_SYNCS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_DOCS_INFOS_SYNCS]') AND name = N'IX_MFR_DOCS_INFOS_SYNCS')
CREATE NONCLUSTERED INDEX [IX_MFR_DOCS_INFOS_SYNCS] ON [MFR_DOCS_INFOS_SYNCS]
(
	[MFR_DOC_ID] ASC,
	[INFO_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
