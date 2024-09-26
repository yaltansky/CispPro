USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_PRIORITIES]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_PRIORITIES](
	[PRIORITY_ID] [int] NOT NULL,
	[NAME] [varchar](32) NULL,
	[CSS_CLASS] [varchar](32) NULL,
 CONSTRAINT [PK_PROJECTS_PRIORITIES] PRIMARY KEY CLUSTERED 
(
	[PRIORITY_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
