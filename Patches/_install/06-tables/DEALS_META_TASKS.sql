/****** Object:  Table [DEALS_META_TASKS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_META_TASKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_META_TASKS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DEAL_TYPE_ID] [int] NULL,
	[TASK_NAME] [varchar](64) NULL,
	[OPTION_KEY] [varchar](64) NULL,
	[BIND_TYPE] [varchar](16) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

