/****** Object:  Table [TASKS_THEMES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TASKS_THEMES]') AND type in (N'U'))
BEGIN
CREATE TABLE [TASKS_THEMES](
	[THEME_ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](64) NULL,
	[NOTE] [varchar](1024) NULL,
	[ANALYZER_ID] [int] NULL,
	[NODE] [hierarchyid] NULL,
	[PARENT_ID] [int] NULL,
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[MAIL_HOST] [varchar](64) NULL,
	[MAIL_PORT] [int] NULL,
	[MAIL_USESSL] [bit] NULL DEFAULT ((0)),
	[MAIL_USERNAME] [varchar](32) NULL,
	[MAIL_PASSWORD] [varchar](max) NULL,
	[DEFAULT_TITLE] [varchar](500) NULL,
	[DEFAULT_EXECTERM] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[THEME_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

