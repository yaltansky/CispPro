
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_TASKS](
	[PROJECT_ID] [int] NOT NULL,
	[TASK_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NOT NULL DEFAULT ((0)),
	[TASK_NUMBER] [int] NULL,
	[NAME] [varchar](500) NOT NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[WK_D_FROM] [datetime] NULL,
	[WK_D_TO] [datetime] NULL,
	[BASE_D_FROM] [datetime] NULL,
	[BASE_D_TO] [datetime] NULL,
	[D_FROM_FACT] [datetime] NULL,
	[D_TO_FACT] [datetime] NULL,
	[D_TO_PREVIOUS] [datetime] NULL,
	[D_AFTER] [datetime] NULL,
	[D_BEFORE] [datetime] NULL,
	[PREDECESSORS] [varchar](max) NULL,
	[DURATION] [float] NULL,
	[DURATION_INPUT] [float] NULL,
	[DURATION_FACT] [float] NULL,
	[DURATION_ID] [int] NULL,
	[DURATION_BUFFER] [int] NULL,
	[PROGRESS] [float] NULL,
	[D_PROGRESS_COMPLETED] [datetime] NULL,
	[IS_NODE] [bit] NULL DEFAULT ((0)),
	[IS_CRITICAL] [bit] NOT NULL DEFAULT ((0)),
	[IS_LONG] [bit] NULL,
	[IS_OVERLONG] [bit] NULL,
	[EXECUTE_LEVEL] [int] NULL,
	[NODE] [hierarchyid] NULL,
	[PARENT_ID] [int] NULL,
	[OUTLINE_LEVEL] [int] NULL DEFAULT ((0)),
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[SORT_ID] [float] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[DESCRIPTION] [varchar](max) NULL,
	[PRIORITY_ID] [int] NULL,
	[TAGS] [varchar](max) NULL,
	[HAS_FILES] [bit] NULL,
	[COUNT_CHECKS] [int] NULL,
	[COUNT_CHECKS_ALL] [int] NULL,
	[COUNT_PAYORDERS] [int] NULL,
	[COUNT_RACI] [varchar](16) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[RESERVED] [varchar](max) NULL,
	[TALK_ID] [int] NULL,
	[D_FROM_DUTY] [datetime] NULL,
	[D_TO_DUTY] [datetime] NULL,
	[REF_PROJECT_ID] [int] NULL,
	[CODE] [varchar](32) NULL,
	[TEMPLATE_TASK_ID] [int] NULL,
	[DURATION_WK_ID] [int] NULL,
	[DURATION_WK_INPUT] [float] NULL,
	[DURATION_WK] [float] NULL,
	[REFKEY] [varchar](250) NULL,
 CONSTRAINT [PK_PROJECTS_TASKS] PRIMARY KEY CLUSTERED 
(
	[TASK_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS]') AND name = N'IX_PROJECTS_TASKS_NODES')
CREATE NONCLUSTERED INDEX [IX_PROJECTS_TASKS_NODES] ON [PROJECTS_TASKS]
(
	[PROJECT_ID] ASC,
	[NODE] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_projects_tasks]'))
EXEC sp_executesql @statement = N'
create trigger [ti_projects_tasks] on [PROJECTS_TASKS]
for insert
as begin
 
	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	update pp
	set task_number = isnull(pp.task_number, tn.new_task_number),
		duration = isnull(pp.duration, 1),
		sort_id = isnull(pp.sort_id, tn.new_task_number),
		has_childs = isnull(pp.has_childs, 0),
		progress = isnull(pp.progress, 0)
	from projects_tasks pp
		join (
			select pp.task_id, isnull(max_task_number,0) + row_number() over (order by pp.task_id) as ''new_task_number''
			from projects_tasks pp
				inner join inserted i on i.task_id = pp.task_id
				left join (
					select project_id, max(task_number) as max_task_number from projects_tasks group by project_id
				) tmax on tmax.project_id = pp.project_id
		) tn on tn.task_id = pp.task_id

end' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_projects_tasks]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_projects_tasks] on [PROJECTS_TASKS]
for insert, update
as
begin

	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(status_id)
	begin
		update projects_tasks
		set is_deleted = case when status_id = -1 then 1 else 0 end
		where task_id in (select task_id from inserted)
	end

	if update(predecessors)
	begin
		update projects_tasks
		set predecessors = null
		where predecessors = ''''
			and task_id in (select task_id from inserted)
	end

	if update(talk_id)
	begin
		update x set talk_id = i.talk_id
		from projects_reps_tasks x
			inner join inserted i on i.task_id = x.task_id
		where i.talk_id is not null
	end

	if update(ref_project_id)
	begin
		update x
		set parent_id = i.project_id
		from projects x
			inner join inserted i on i.ref_project_id = x.project_id
	end

end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_projects_tasks_progress]'))
EXEC sp_executesql @statement = N'
create trigger [tu_projects_tasks_progress] on [PROJECTS_TASKS]
for update
as
begin

	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(progress) or update(d_from_fact) or update(d_to_fact)
	begin
		declare 
			@d_from_fact datetime,
			@d_to_fact datetime,
			@today datetime; set @today = dbo.today()

		update t
		set @d_from_fact = 
				case
					when t.progress = 1 then isnull(t.d_from_fact, dbo.work_day_add(@today, -t.duration))
					else t.d_from_fact
				end,

			@d_to_fact =
				case
					when t.progress = 1 then isnull(t.d_to_fact, @today)
					else null
				end,

			duration_fact = 
				case
					when t.progress = 1 then dbo.work_day_diff(@d_from_fact, @d_to_fact)
					else null
				end,

			d_from_fact = @d_from_fact,
			d_to_fact = @d_to_fact,
			d_progress_completed = case when t.progress = 1 then isnull(t.d_progress_completed, getdate()) end

		from projects_tasks t
			inner join deleted d on d.task_id = t.task_id
		where t.task_id in (select task_id from inserted)
			and t.has_childs = 0
	end

end
' 
GO
