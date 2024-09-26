USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_DURATIONS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_DURATIONS](
	[DURATION_ID] [int] NOT NULL,
	[NAME] [varchar](12) NULL,
	[FACTOR] [float] NULL,
	[FACTOR24] [float] NULL,
 CONSTRAINT [PK_PROJECTS_DURATIONS] PRIMARY KEY CLUSTERED 
(
	[DURATION_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
