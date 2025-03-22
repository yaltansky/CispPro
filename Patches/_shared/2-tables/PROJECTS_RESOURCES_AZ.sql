
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_RESOURCES_AZ]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_RESOURCES_AZ](
	[PROJECT_ID] [int] NULL,
	[RESOURCE_ID] [int] NULL,
	[D_DOC] [date] NULL,
	[LIMIT_Q] [float] NULL,
	[LIMIT_V] [float] NULL,
	[PRICE] [float] NULL,
	[TASK_ID] [int] NULL,
	[PLAN_Q] [float] NULL,
	[PLAN_V] [float] NULL,
	[MOL_ID] [int] NULL,
	[FACT_Q] [float] NULL,
	[FACT_V] [float] NULL,
	[D_CALC] [datetime] NULL DEFAULT (getdate())
)
END
GO
