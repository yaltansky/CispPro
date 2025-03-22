
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_DUTIES]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_DUTIES](
	[PROJECT_ID] [int] NOT NULL,
	[TASK_ID] [int] NOT NULL,
	[NAME] [varchar](500) NOT NULL,
	[DESCRIPTION] [varchar](max) NULL,
	[D_FROM] [datetime] NULL,
	[D_FROM_FACT] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[D_TO_FACT] [datetime] NULL,
	[PROGRESS] [decimal](18, 2) NULL,
	[DURATION] [float] NULL,
	[NODE] [hierarchyid] NULL,
	[PARENT_ID] [int] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[LEVEL_ID] [int] NULL DEFAULT ((0)),
	[SORT_ID] [float] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[PRIORITY_ID] [int] NULL,
	[HAS_FILES] [bit] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[D_TO_CALC] [datetime] NULL,
PRIMARY KEY CLUSTERED 
(
	[TASK_ID] ASC
)
)
END
GO

