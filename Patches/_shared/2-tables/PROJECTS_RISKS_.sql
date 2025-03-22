
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_RISKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_RISKS](
	[PROJECT_ID] [int] NOT NULL,
	[RISK_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NULL,
	[NAME] [varchar](250) NOT NULL,
	[D_LAST_REPORT] [datetime] NULL,
	[CATEGORY_ID] [int] NULL,
	[PROBABILITY] [float] NULL,
	[INFLUENCE] [float] NULL,
	[RESULT_VALUE] [float] NULL,
	[NOTE] [varchar](max) NULL,
	[TALK_ID] [int] NULL,
	[NODE] [hierarchyid] NULL,
	[PARENT_ID] [int] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[LEVEL_ID] [int] NULL DEFAULT ((0)),
	[SORT_ID] [float] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[MOL_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
PRIMARY KEY CLUSTERED 
(
	[RISK_ID] ASC
)
)
END
GO

