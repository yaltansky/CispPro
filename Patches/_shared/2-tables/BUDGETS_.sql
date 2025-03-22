IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[BUDGETS]') AND type in (N'U'))
BEGIN
CREATE TABLE [BUDGETS](
	[BUDGET_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NOT NULL DEFAULT ((1)),
	[NOTE] [varchar](255) NULL,
	[PROJECT_ID] [int] NULL,
	[ADD_DATE] [datetime] NOT NULL DEFAULT (getdate()),
	[MOL_ID] [int] NOT NULL,
	[MAIN_ID] [int] NULL,
	[IS_WBS] [bit] NULL,
	[NAME] [varchar](255) NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[CONTENT] [varchar](max) NULL,
	[INHERITED_ACCESS] [bit] NOT NULL DEFAULT ((0)),
	[TYPE_ID] [int] NOT NULL DEFAULT ((1)),
	[IS_DELETED]  AS (case when [STATUS_ID]=(-1) then (1) else (0) end),
	[SUBJECT_ID] [int] NULL,
	[PERIOD_ID] [varchar](16) NULL,
 CONSTRAINT [PK_BUDGETS] PRIMARY KEY CLUSTERED 
(
	[BUDGET_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[BUDGETS]') AND name = N'IX_BUDGETS_1')
CREATE NONCLUSTERED INDEX [IX_BUDGETS_1] ON [BUDGETS]
(
	[NAME] ASC
)
GO

IF not EXISTS (SELECT * FROM sys.fulltext_indexes fti WHERE fti.object_id = OBJECT_ID(N'[BUDGETS]'))
CREATE FULLTEXT INDEX ON [BUDGETS](
[CONTENT] LANGUAGE 'English')
KEY INDEX [PK_BUDGETS]ON ([CATALOG], FILEGROUP [PRIMARY])
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_budgets_content]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_budgets_content] on [BUDGETS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	if update(name) or update(project_id)
		update x
		set content = concat(
				x.name, ''#'',
				p.name
				)
		from budgets x
			left join projects p on p.project_id = x.project_id
		where x.budget_id in (select budget_id from inserted)

end' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_budgets_projects]'))
EXEC sp_executesql @statement = N'create trigger [tiu_budgets_projects] on [BUDGETS]
for insert, update as
begin

	if update(project_id)	
	begin
		if exists(
			select 1 from deals x
				join inserted i on i.project_id = x.deal_id
			where isnull(x.budget_id,0) <> i.budget_id
			)
			update x set budget_id = i.budget_id
			from deals x
				join inserted i on i.project_id = x.deal_id
			where isnull(x.budget_id,0) <> i.budget_id

		if exists(
			select 1 from budgets x
				join projects p on p.project_id = x.project_id
			where isnull(x.type_id,0) <> p.type_id
			)
			update x set type_id = p.type_id
			from budgets x
				join projects p on p.project_id = x.project_id
			where isnull(x.type_id,0) <> p.type_id
	end
end' 
GO
