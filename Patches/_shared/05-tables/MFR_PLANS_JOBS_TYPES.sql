USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_TYPES]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_PLANS_JOBS_TYPES](
	[TYPE_ID] [int] NOT NULL,
	[NAME] [varchar](30) NULL,
	[SHORT_NAME] [varchar](10) NULL,
	[SLICE] [varchar](20) NULL,
 CONSTRAINT [PK_MFR_PLANS_JOBS_TYPES] PRIMARY KEY CLUSTERED 
(
	[TYPE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
