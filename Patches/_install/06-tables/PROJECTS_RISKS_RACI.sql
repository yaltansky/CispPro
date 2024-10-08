/****** Object:  Table [PROJECTS_RISKS_RACI]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_RISKS_RACI]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_RISKS_RACI](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[RISK_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[RACI] [varchar](10) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

