
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TASKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [TASKS](
	[TASK_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NOT NULL,
	[D_DOC] [datetime] NOT NULL DEFAULT cast(getdate() as date),
	[D_DEADLINE] [datetime] NULL,
	[TITLE] [varchar](512) NULL,
	[AUTHOR_ID] [int] NOT NULL,
	[ANALYZER_ID] [int] NULL,
	[OWNER_ID] [int] NULL,
	[PROJECT_TASK_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[D_DEADLINE_AUTHOR] [datetime] NULL,
	[D_DEADLINE_ANALYZER] [datetime] NULL,
	[REFKEY] [varchar](250) NULL,
	[TYPE_ID] [int] NOT NULL DEFAULT ((1)),
	[REFNAME] [varchar](150) NULL,
	[EXECUTOR_NAME] [varchar](150) NULL,
	[THEME_ID] [int] NULL,
	[PARENT_ID] [int] NULL,
	[NODE] [hierarchyid] NULL,
	[HAS_CHILDS] [bit] NULL,
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[D_CLOSED] [datetime] NULL,
	[RESERVED] [varchar](max) NULL,
	[D_CLOSED_PLAN] [date] NULL,
PRIMARY KEY CLUSTERED 
(
	[TASK_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[TASKS]') AND name = N'IX_TASKS_REFKEY')
CREATE NONCLUSTERED INDEX [IX_TASKS_REFKEY] ON [TASKS]
(
	[REFKEY] ASC
)
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_tasks]'))
EXEC sp_executesql @statement = N'create trigger [ti_tasks] on [TASKS]
for insert
as begin
 
	set nocount on;
	
	update t
	set title = concat(p.name, '' / '', isnull(t.title, pt.name)),
		d_deadline = isnull(t.d_deadline, pt.d_to),
		analyzer_id = isnull(t.analyzer_id,
			(select top 1 mol_id from projects_tasks_raci where task_id = pt.task_id and raci like ''%R%'')
			)
	from tasks t
		join projects_tasks pt on pt.task_id = t.project_task_id
		    join projects p on p.project_id = pt.project_id
	where t.task_id in (select task_id from inserted)

end' 
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_tasks]'))
EXEC sp_executesql @statement = N'create trigger [tiu_tasks] on [TASKS]
for insert, update
as begin
 
	set nocount on;
	
	if update(type_id) or update(refkey)
	begin
		update tasks
		set theme_id = isnull(theme_id,
				case
					when type_id = 1 then
						case
							when refkey like ''/documents/%'' then 5
							else 2
						end
					when type_id = 2 then
						case
							when refkey like ''/finance/payorders/%'' then 6
							else 3
						end						
					when type_id = 3 then 4
				end
				)
		where task_id in (select task_id from inserted)
	end

	if update(analyzer_id)
	begin
		insert into tasks_mols(task_id, mol_id, role_id)
		select task_id, analyzer_id, 20
		from inserted i
		where not exists(select 1 from tasks_mols where task_id = i.task_id and mol_id = i.analyzer_id and role_id = 20)
			and i.analyzer_id is not null
	end

	if update(status_id)
		update x set status_id = 5
		from tasks_mols x
			join inserted i on i.task_id = x.task_id
		where i.status_id = 5
			and isnull(x.status_id,0) <> 5
			and x.role_id = 1 -- исполнитель

end
' 
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_tasks_project_id]'))
EXEC sp_executesql @statement = N'create trigger [tiu_tasks_project_id] on [TASKS]
for insert, update
as begin
 
	set nocount on;
	
	if update(project_task_id)
	begin
		update tasks
		set refkey = ''/projects/'' + cast(pt.project_id as varchar) + ''/plan/'' + cast(pt.task_id as varchar)
		from tasks t
			inner join inserted i on i.task_id = t.task_id
				inner join projects_tasks pt on pt.task_id = i.project_task_id
	end
	
end
' 
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_tasks_refs]'))
EXEC sp_executesql @statement = N'create trigger [tiu_tasks_refs] on [TASKS]
for insert, update
as begin
 
	set nocount on;
	
	if update(refkey)
	begin
		update x
		set refname = p.name
		from tasks x
			join (
				select 
					task_id,
					try_parse(
						substring(refkey, 11, 
							charindex(''/'', substring(refkey, 11, 20)) - 1
							)
						as int) as project_id
				from tasks
				where charindex(''/projects/'', refkey) = 1
					and charindex(''/projects/deals'', refkey) = 0
			) xx on xx.task_id = x.task_id
				join projects p on p.project_id = xx.project_id
		where x.task_id in (select task_id from inserted)
	end

end
' 
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_tasks_deadline]'))
EXEC sp_executesql @statement = N'create trigger [tu_tasks_deadline] on [TASKS]
for update
as begin
 
	set nocount on;
	
	if update(d_deadline_author) or update(d_deadline_analyzer)
	begin
		update tasks
		set d_deadline = isnull(d_deadline_author, d_deadline_analyzer)
		where task_id in (select distinct task_id from inserted)
	end

end
' 
GO
