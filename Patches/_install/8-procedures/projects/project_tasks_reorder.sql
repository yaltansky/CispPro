if object_id('project_tasks_reorder') is not null drop proc project_tasks_reorder
go
create proc project_tasks_reorder
	@project_id int,
	@calctree bit = 0
as begin

	set nocount on;

	if exists(select 1 from projects_tasks where project_id = @project_id and parent_id = task_id)
		or @calctree = 1
		exec project_tasks_reorder;2 @project_id

	create table #ptr_tasks(task_id int primary key, task_number int)
		insert into #ptr_tasks(task_id, task_number)
		select task_id, task_number from (
			select 
				task_id, 
				row_number() over (order by node) as task_number,
				task_number as old_task_number
			from projects_tasks
			where project_id = @project_id and is_deleted = 0
			) x
		where @calctree = 1 or x.task_number != isnull(x.old_task_number,0)

	if exists(select 1 from #ptr_tasks)
	begin
		exec sys_set_triggers 0
			-- task_number
			update pp
			set task_number = tn.task_number,
				sort_id = tn.task_number
			from projects_tasks pp
				join #ptr_tasks tn on tn.task_id = pp.task_id
			where pp.project_id = @project_id
			-- predecessors
			exec project_tasks_calc_predecessors @project_id = @project_id
		exec sys_set_triggers 1
	end

end
GO
-- helper: hierarchyid
create proc project_tasks_reorder;2
	@project_id int
as begin

	declare @children tree_nodes
		insert @children(node_id, parent_id, num)
		select task_id, parent_id,  
		  row_number() over (partition by parent_id order by parent_id, node, task_number)
		from projects_tasks where project_id = @project_id
			and is_deleted = 0

    create table #ptr_nodes(
        node_id int primary key,
        parent_id int null,
        num int null,
        node hierarchyid null,
        level_id int null
        )
        insert into #ptr_nodes exec tree_calc @children

	exec sys_set_triggers 0
		-- clear
		update projects_tasks set node = null where project_id = @project_id
		
		-- node, outline_level
		update x
		set node = xx.node,
			outline_level = xx.level_id
		from projects_tasks x
			join #ptr_nodes as xx on xx.node_id = x.task_id
		where x.project_id = @project_id

		-- mark as deleted
		-- update projects_tasks set status_id = -1, is_deleted = 1 where project_id = @project_id and node is null 

		-- has_childs
		update p
		set has_childs = 
				case 
					when exists(select 1 from projects_tasks where project_id = @project_id and parent_id = p.task_id and is_deleted = 0) 
					then 1 
				else 0 end
		from projects_tasks p
		where project_id = @project_id
			and is_deleted = 0

	exec sys_set_triggers 1
end
go
