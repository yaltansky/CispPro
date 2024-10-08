if object_id('project_tasks_check') is not null drop proc project_tasks_check
go
create proc [project_tasks_check]
	@project_id int
as
begin

	set nocount on;

-- auto-calendar
	exec calendar_calc

-- delete unused tasks
	delete from projects_tasks where project_id = @project_id and status_id = -1

	-- ... and all their childs
	;with tree(task_id) as (
		select distinct parent_id as task_id
		from projects_tasks
		where project_id = @project_id
			and parent_id is not null
			and parent_id not in (select task_id from projects_tasks where project_id = @project_id)
		union all
		select t.task_id
		from projects_tasks t
			inner join tree on tree.task_id = t.parent_id
		)
		delete from projects_tasks where task_id in (select task_id from tree)

-- check for cycle refs

	-- clear error
	update projects_tasks
	set priority_id = null
	where project_id = @project_id
		and priority_id = -1
	
	-- check error
	update projects_tasks
	set priority_id = -1
	where project_id = @project_id
		and task_id in (
				select target_id from projects_tasks_links 
				where source_id in (
						select task_id from projects_tasks 
						where project_id = @project_id and priority_id = -1
						)
				)

	if exists(select 1 from projects_tasks where project_id = @project_id and priority_id = -1)
	begin
		raiserror('Есть ошибки в Плане проекта, которые отмечены значком "!". Необходимо устранить ошибки Плана проекта.', 16, 1)
		return
	end

	-- delete bad logical links (когда дочерние задачи зависят от родительских, которые, по сути, являются агрегаторами)
	delete l
	from projects_tasks_links l
		inner join projects_tasks t on t.task_id = l.target_id
	where l.source_id = t.parent_id
		and l.project_id = @project_id

-- check duration
	update projects_tasks
	set duration = 1
	where project_id = @project_id
		and has_childs = 0
		and duration is null

-- check progress
	update projects_tasks
	set progress = 0
	where project_id = @project_id
		and has_childs = 0
		and progress is null

end
GO

-- post-проверка на адекватность
create proc [project_tasks_check];10
	@project_id int
as
begin

	set nocount on;
		
	if (select abs(max(duration_buffer)) from projects_tasks where project_id = @project_id)
		> (select datediff(d, d_from, d_to_forecast ) from projects where project_id = @project_id)
	begin
		raiserror('Максимальный буфер задач проекта слишком большой. Результаты расчёта сохранены автоматически для анализа контекста.', 16, 1)
	end

end
GO
