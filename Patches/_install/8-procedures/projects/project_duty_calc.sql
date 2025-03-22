if object_id('project_duty_calc') is not null drop proc project_duty_calc
go
create proc project_duty_calc
	@project_id int
as
begin

	set nocount on;

-- @childs
	declare @childs table(task_id int, node hierarchyid)
	insert into @childs(task_id, node)	
	select task_id, node from projects_tasks where project_id = @project_id and d_from_duty is not null
	
-- @tasks = @childs + parents
	declare @tasks table(task_id int primary key)
	insert into @tasks(task_id)
		select distinct pt.task_id
		from projects_tasks pt
			join @childs c on c.node.IsDescendantOf(pt.node) = 1
		where pt.project_id = @project_id

-- projects_duties
	declare @olds table(task_id int primary key, name varchar(500), description varchar(max))

	delete from projects_duties 
		output deleted.task_id, deleted.name, deleted.description into @olds
	where project_id = @project_id

	insert into projects_duties(
		project_id, task_id, name, description,
		d_from, d_from_fact, d_to, d_to_calc, d_to_fact, progress, duration,
		node, parent_id, has_childs, level_id, sort_id)
	select 
		project_id, task_id, name, description,
		d_from_duty, d_from_fact, d_to_duty, d_to, d_to_fact, progress, duration,
		node, parent_id, has_childs, outline_level, sort_id
	from projects_tasks
	where task_id in (select task_id from @tasks)
	
	-- olds
	update x
	set name = d.name,
		description = d.description
	from projects_duties x
		inner join @olds d on d.task_id = x.task_id
	where x.project_id = @project_id

	-- has_childs
	update x
	set has_childs = 
			case
				when exists(select 1 from projects_duties where project_id = @project_id and parent_id = x.task_id) then 1
				else 0
			end
	from projects_duties x
	where x.project_id = @project_id

-- calc summary
	update x
	set d_from = r.d_from,
		d_to = r.d_to,
		progress = r.progress
	from projects_duties x
		inner join (
			select y2.task_id, 
				min(y1.d_from) as d_from,
				max(y1.d_to) as d_to,
				case
					when sum(y1.duration) > 0 then sum(y1.duration*y1.progress) / sum(y1.duration)
				end as progress
			from projects_duties y1
				join projects_duties y2 on y2.project_id = y1.project_id and y1.node.IsDescendantOf(y2.node) = 1 and y1.has_childs = 0
			where y2.has_childs = 1
			group by y2.task_id
		) r on r.task_id = x.task_id
	where x.project_id = @project_id

end
go
