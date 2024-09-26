/****** Object:  Table [DEALS_MAP_STAGES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_MAP_STAGES]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_MAP_STAGES](
	[STAGE_ID] [int] NULL,
	[STAGE_NAME] [varchar](50) NULL,
	[TASK_NAME] [varchar](50) NULL
) ON [PRIMARY]
END
GO

