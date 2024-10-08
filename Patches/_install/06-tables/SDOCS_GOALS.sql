/****** Object:  Table [SDOCS_GOALS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_GOALS]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_GOALS](
	[PARENT_ID] [int] NULL,
	[GOAL_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NOT NULL DEFAULT ((1)),
	[SUBJECT_ID] [int] NULL,
	[STOCK_ID] [int] NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[NAME] [nvarchar](250) NULL,
	[NOTE] [nvarchar](max) NULL,
	[MOL_ID] [int] NULL,
	[ADD_DATE] [datetime] NOT NULL DEFAULT (getdate()),
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[GOAL_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO
