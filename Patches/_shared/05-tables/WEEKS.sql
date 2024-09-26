USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[WEEKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [WEEKS](
	[WEEK_ID] [int] NOT NULL,
	[NAME] [varchar](24) NULL,
	[WEEK_NUMBER] [varchar](24) NULL,
	[YEAR] [int] NULL,
	[D_FROM] [datetime] NOT NULL,
	[D_TO] [datetime] NOT NULL,
	[PERIOD_ID] [int] NULL,
 CONSTRAINT [PK_WEEKS] PRIMARY KEY CLUSTERED 
(
	[WEEK_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
