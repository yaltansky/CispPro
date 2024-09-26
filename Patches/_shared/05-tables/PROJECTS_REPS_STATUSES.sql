USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_REPS_STATUSES]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_REPS_STATUSES](
	[STATUS_ID] [int] NOT NULL,
	[NAME] [varchar](20) NULL,
 CONSTRAINT [PK_PROJECTS_REPS_STATUSES] PRIMARY KEY CLUSTERED 
(
	[STATUS_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
