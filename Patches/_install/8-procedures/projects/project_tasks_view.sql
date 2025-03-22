if object_id('project_tasks_view') is not null drop proc project_tasks_view
go
create proc project_tasks_view
	@project_id int,	
	@mol_id int = null,
	@view_id int = 1,
	@extra_id int = null,
	@task_id int = null,
	@parent_id int = null,
	@priority_id int = null,
	@search varchar(50) = null,
	@ids varchar(max) = null,
	@raci_mol_id int = null,
	@raci_mask varchar(16) = null,
	@event_id int = null,
	@root_id int = null
as
begin

	set nocount on;

	create table #tasks(task_id int index ix_task)

-- #tasks
	if @ids is not null
	begin
		-- expanded parents
		insert into #tasks select distinct item from dbo.str2rows(@ids, ',')

		-- + their childs
		insert into #tasks(task_id)
		select t.task_id
		from projects_tasks t
			inner join #tasks tt on tt.task_id = t.parent_id
		where t.project_id = @project_id

		-- + root
		insert into #tasks(task_id)
		select task_id from projects_tasks
		where project_id = @project_id and isnull(@root_id,0) = isnull(parent_id,0)
	end

	else if @task_id is not null
	begin
		insert into #tasks select @task_id
	end

	else
	begin
		if dbo.hashid(@search) is not null
		begin
			set @task_id = dbo.hashid(@search)
			select @project_id = project_id from projects_tasks where task_id = @task_id
		end

		insert into #tasks
		exec project_tasks_search @project_id = @project_id, @mol_id = @mol_id, @search = @search, @priority_id = @priority_id, @extra_id = @extra_id,
			@raci_mol_id = @raci_mol_id, @raci_mask = @raci_mask, @event_id = @event_id, @root_id = @root_id, @parent_id = @parent_id
	end

-- final select
	declare @root_level_id int
	set @root_level_id = isnull(
		(select outline_level-1 from projects_tasks where task_id = @root_id)
		,0)

	select
        x.PROJECT_ID,
        PARENT_ID = case when x.task_id <> isnull(@root_id,0) then x.parent_id end,
        x.TASK_ID,
        x.STATUS_ID,
        x.TASK_NUMBER,
        x.NAME,
		x.DESCRIPTION,
        D_FROM = case when @view_id = 2 then x.base_d_from else x.d_from end,
		D_FROM_FACT = case when x.HAS_CHILDS = 0 then  x.D_FROM_FACT end,
        D_TO = case when @view_id = 2 then x.base_d_to else x.d_to end,
		D_TO_FACT = case when x.HAS_CHILDS = 0 then x.D_TO_FACT end,
        x.D_AFTER,
        x.D_BEFORE,
        x.DURATION,
		x.DURATION_INPUT,
		x.DURATION_ID,
        x.PROGRESS,
        x.PREDECESSORS,
        x.IS_NODE,
        x.HAS_CHILDS,
        x.SORT_ID,
        x.COUNT_CHECKS,
        x.COUNT_CHECKS_ALL,
		x.COUNT_RACI,
		x.COUNT_PAYORDERS,
        x.PRIORITY_ID,
		PRIORITY_CSS_CLASS = pr.css_class,
        x.TAGS,
        x.IS_CRITICAL,
        x.IS_LONG,
		x.IS_OVERLONG,
        x.EXECUTE_LEVEL,
        OUTLINE_LEVEL = x.OUTLINE_LEVEL - @root_level_id,
        x.DURATION_BUFFER,
        x.HAS_FILES,

		HAS_RESOURCES = cast(
			case
				when exists(select 1 from projects_tasks_resources where task_id = x.task_id) then 1
				else 0
			end as bit),
		
		x.TALK_ID,
		x.REF_PROJECT_ID
	from projects_tasks x
		left join projects_priorities pr on pr.priority_id = x.priority_id
	where x.is_deleted = 0
		and x.task_id in (select task_id from #tasks)
	order by x.sort_id, x.task_number

	drop table #tasks
end
go
