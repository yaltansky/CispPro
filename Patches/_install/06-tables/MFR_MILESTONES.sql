/****** Object:  Table [MFR_MILESTONES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_MILESTONES]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_MILESTONES](
	[MILESTONE_ID] [int] NOT NULL,
	[NAME] [varchar](50) NULL,
PRIMARY KEY CLUSTERED 
(
	[MILESTONE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

