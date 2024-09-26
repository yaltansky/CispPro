/****** Object:  Table [MFR_DOCS_INFOS_HISTS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_DOCS_INFOS_HISTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_DOCS_INFOS_HISTS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[MFR_DOC_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO
