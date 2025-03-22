
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DUMP_PROJECTS_TASKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DUMP_PROJECTS_TASKS](
	[DUMP_ID] [varchar](32) NULL,
	[PROJECT_ID] [int] NOT NULL,
	[PARENT_ID] [int] NULL,
	[TASK_ID] [int] NULL,
	[STATUS_ID] [int] NULL,
	[TASK_NUMBER] [int] NULL,
	[NAME] [varchar](500) NOT NULL,
	[MOL_ID] [int] NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[BASE_D_FROM] [datetime] NULL,
	[BASE_D_TO] [datetime] NULL,
	[REVERSE_D_FROM] [datetime] NULL,
	[REVERSE_D_TO] [datetime] NULL,
	[DURATION] [decimal](18, 2) NULL,
	[PROGRESS] [decimal](18, 2) NULL,
	[PREDECESSORS] [varchar](max) NULL,
	[RESOURCE_NAMES] [varchar](max) NULL,
	[HAS_CHILDS] [bit] NULL,
	[DESCRIPTION] [varchar](max) NULL,
	[SORT_ID] [float] NULL,
	[IS_CRITICAL] [bit] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[COUNT_CHECKS] [int] NULL,
	[COUNT_CHECKS_ALL] [int] NULL,
	[PRIORITY_ID] [int] NULL,
	[OUTLINE_LEVEL] [int] NULL,
	[D_AFTER] [datetime] NULL,
	[TAGS] [varchar](max) NULL,
	[IS_LONG] [bit] NULL,
	[DURATION_BUFFER] [int] NULL,
	[EXECUTE_LEVEL] [int] NULL,
	[HAS_FILES] [bit] NULL,
	[D_BEFORE] [datetime] NULL,
	[IS_NODE] [bit] NULL,
	[D_BEFORE_DIFF] [int] NULL,
	[RESERVED] [varchar](max) NULL
)
END
GO

