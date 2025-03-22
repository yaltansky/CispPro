
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FIN_GOALS_ACCOUNTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FIN_GOALS_ACCOUNTS](
	[GOAL_ACCOUNT_ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](100) NULL,
	[SHORT_NAME] [varchar](6) NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[PARENT_ID] [int] NULL,
	[NODE_ID] [int] NOT NULL,
	[NODE] [hierarchyid] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[LEVEL_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[SORT_ID] [float] NULL,
PRIMARY KEY CLUSTERED 
(
	[GOAL_ACCOUNT_ID] ASC
)
)
END
GO

