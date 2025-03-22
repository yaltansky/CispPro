if object_id('projects_tasks_view') is not null drop proc projects_tasks_view
go

create proc projects_tasks_view
	@chief_id int = null,
	@search varchar(64) = null,
	@execute_level int = 2
as
begin

	set nocount on;

-- childs
	declare @childs table(task_id int)
	insert into @childs select task_id
		from projects_tasks
		where progress < 1
			and has_childs = 0
			and (is_critical = 1 or is_long = 1)
			and execute_level <= @execute_level
			and project_id in (
				select project_id from projects 
				where status_id in (2,3,4)
					and (@chief_id is null or chief_id = @chief_id)
				)
			and (@search is null or charindex(@search, name) > 0)

-- calc tree: childs + all parents
	declare @tree table(parent_id int, task_id int)
		
	;with tree as (
		select parent_id, task_id from projects_tasks where task_id in (select task_id from @childs)
		union all
		select t.parent_id, t.task_id
		from projects_tasks t
			inner join tree on tree.parent_id = t.task_id
		)
		insert into @tree select distinct parent_id, task_id from tree
		
-- #tasks
	-- tasks tree
	select
		OBJ_TYPE = 'PTS',
		OBJ_ID = x.TASK_ID,
        x.PROJECT_ID,
        x.TASK_NUMBER,
		PROJECT_NAME = prj.NAME,
        x.NAME,
        x.D_FROM,
        x.D_TO,
        x.DURATION,
        x.PROGRESS,
        x.HAS_CHILDS,
        x.IS_CRITICAL,
        x.IS_LONG,
		x.IS_OVERLONG,
        x.EXECUTE_LEVEL,
        OUTLINE_LEVEL = x.OUTLINE_LEVEL,
        x.DURATION_BUFFER,
		x.SORT_ID
	into #tasks
	from projects_tasks x		
		inner join projects prj on prj.project_id = x.project_id
	where x.task_id in (select task_id from @tree)

	-- add projects
	insert into #tasks(
		obj_type, obj_id, project_id, task_number, project_name, name,
		d_from, d_to, duration, progress,
		has_childs, is_critical, is_long, is_overlong,
		execute_level, outline_level, duration_buffer, sort_id
	)
	select distinct
		'PRJ', project_id, project_id, 0, name, name, 
		x.d_from, x.d_to, datediff(d, x.d_from, x.d_to), x.progress,
		1, 0, 0, 0,
		0, 0, 0, 0
	from projects x
	where project_id in (select project_id from #tasks)
		
-- final select
	select
		OBJ_TYPE, OBJ_ID, PROJECT_ID, TASK_NUMBER, NAME,
		D_FROM, D_TO, DURATION, PROGRESS, DURATION_BUFFER,
		HAS_CHILDS, IS_CRITICAL, IS_LONG, IS_OVERLONG,
		EXECUTE_LEVEL, OUTLINE_LEVEL, SORT_ID
	from #tasks
	order by project_name, sort_id, task_number

end
go

