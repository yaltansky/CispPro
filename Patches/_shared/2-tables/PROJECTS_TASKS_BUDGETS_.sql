
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS_BUDGETS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_TASKS_BUDGETS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PROJECT_ID] [int] NULL,
	[BUDGET_ID] [int] NULL,
	[TASK_ID] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[BUDGET_PERIOD_ID] [int] NULL,
	[PLAN_DDS] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[MOL_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[FACT_DDS] [decimal](18, 2) NULL,
	[PLAN_BDR] [decimal](18, 2) NULL,
	[HAS_DETAILS] [bit] NOT NULL DEFAULT ((0)),
	[RESERVED] [int] NULL,
	[D_DOC_CALC] [datetime] NULL,
	[DATE_TYPE_ID] [int] NULL,
	[DATE_LAG] [int] NULL,
	[TEMPLATE_REF_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS_BUDGETS]') AND name = N'IX_PROJECTS_TASKS_BUDGETS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PROJECTS_TASKS_BUDGETS] ON [PROJECTS_TASKS_BUDGETS]
(
	[BUDGET_ID] ASC,
	[TASK_ID] ASC,
	[ARTICLE_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PROJECTS_TASKS_BUDGETS_TASK_ID]') AND parent_object_id = OBJECT_ID(N'[PROJECTS_TASKS_BUDGETS]'))
ALTER TABLE [PROJECTS_TASKS_BUDGETS]  WITH CHECK ADD  CONSTRAINT [FK_PROJECTS_TASKS_BUDGETS_TASK_ID] FOREIGN KEY([TASK_ID])
REFERENCES [PROJECTS_TASKS] ([TASK_ID])
ON DELETE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PROJECTS_TASKS_BUDGETS_TASK_ID]') AND parent_object_id = OBJECT_ID(N'[PROJECTS_TASKS_BUDGETS]'))
ALTER TABLE [PROJECTS_TASKS_BUDGETS] CHECK CONSTRAINT [FK_PROJECTS_TASKS_BUDGETS_TASK_ID]
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_projects_tasks_budgets]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_projects_tasks_budgets] on [PROJECTS_TASKS_BUDGETS]
for insert, update
as
begin

	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(article_id) or update(plan_bdr) or update(plan_dds)
	begin
		update x
		set plan_bdr = 
				case
					when a.direction is not null then a.direction * abs(x.plan_bdr)
					else x.plan_bdr
				end,
			plan_dds = 
				case
					when a.direction is not null then a.direction * abs(x.plan_dds)
					else x.plan_dds
				end
		from projects_tasks_budgets x
			inner join bdr_articles a on a.article_id = x.article_id
			inner join inserted i on i.id = x.id
	end		

end' 
GO
