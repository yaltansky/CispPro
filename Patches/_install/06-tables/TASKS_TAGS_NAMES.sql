/****** Object:  Table [TASKS_TAGS_NAMES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TASKS_TAGS_NAMES]') AND type in (N'U'))
BEGIN
CREATE TABLE [TASKS_TAGS_NAMES](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[MOL_ID] [int] NOT NULL,
	[NAME] [varchar](max) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

