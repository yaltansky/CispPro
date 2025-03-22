
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DUMP_PROJECTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DUMP_PROJECTS](
	[DUMP_ID] [varchar](32) NULL,
	[PROJECT_ID] [int] NULL,
	[GROUP_ID] [int] NULL,
	[NAME] [varchar](255) NOT NULL,
	[GOAL] [varchar](max) NULL,
	[CURATOR_ID] [int] NOT NULL,
	[ADMIN_ID] [int] NOT NULL,
	[CHIEF_ID] [int] NOT NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[D_TO_MIN] [datetime] NULL,
	[STATUS_ID] [int] NOT NULL,
	[NOTE] [varchar](max) NULL,
	[PROGRESS] [decimal](3, 2) NULL,
	[PROGRESS_CRITICAL] [decimal](3, 2) NULL,
	[PROGRESS_EXEC] [decimal](3, 2) NULL,
	[PROGRESS_SPEED] [decimal](3, 2) NULL,
	[PROGRESS_LAG] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[D_TO_FORECAST] [datetime] NULL,
	[DUMP_IDD] [int] IDENTITY(1,1) NOT NULL,
	[DUMP_DATE] [datetime] DEFAULT getdate()
)
END
GO
