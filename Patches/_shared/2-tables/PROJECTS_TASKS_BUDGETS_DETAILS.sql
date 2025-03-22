
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS_BUDGETS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_TASKS_BUDGETS_DETAILS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PARENT_ID] [int] NOT NULL,
	[DATE_TYPE_ID] [int] NULL,
	[DATE_LAG] [int] NULL,
	[D_DOC] [datetime] NULL,
	[BUDGET_PERIOD_ID] [int] NULL,
	[RATIO] [float] NULL,
	[PLAN_DDS] [decimal](18, 2) NULL,
	[PLAN_BDR] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[MOL_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[FACT_DDS] [decimal](18, 2) NULL,
	[D_DOC_CALC] [datetime] NULL,
	[PROJECT_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PROJECTS_TASKS_BUDGETS_DETAILS_PARENT_ID]') AND parent_object_id = OBJECT_ID(N'[PROJECTS_TASKS_BUDGETS_DETAILS]'))
ALTER TABLE [PROJECTS_TASKS_BUDGETS_DETAILS]  WITH CHECK ADD  CONSTRAINT [FK_PROJECTS_TASKS_BUDGETS_DETAILS_PARENT_ID] FOREIGN KEY([PARENT_ID])
REFERENCES [PROJECTS_TASKS_BUDGETS] ([ID])
ON DELETE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PROJECTS_TASKS_BUDGETS_DETAILS_PARENT_ID]') AND parent_object_id = OBJECT_ID(N'[PROJECTS_TASKS_BUDGETS_DETAILS]'))
ALTER TABLE [PROJECTS_TASKS_BUDGETS_DETAILS] CHECK CONSTRAINT [FK_PROJECTS_TASKS_BUDGETS_DETAILS_PARENT_ID]
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_projects_tasks_budgets_details]'))
EXEC sp_executesql @statement = N'create trigger [tiu_projects_tasks_budgets_details] on [PROJECTS_TASKS_BUDGETS_DETAILS]
for insert, update
as
begin

	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(parent_id)
		update x
		set project_id = xx.project_id
		from projects_tasks_budgets_details x
			join projects_tasks_budgets xx on xx.id = x.parent_id
			join inserted i on i.id = x.id

	if update(plan_bdr) or update(plan_dds)
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
		from projects_tasks_budgets_details x
			join projects_tasks_budgets xx on xx.id = x.parent_id
				join bdr_articles a on a.article_id = xx.article_id
			join inserted i on i.id = x.id
	end		

end' 
GO
