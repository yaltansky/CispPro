if object_id('project_tasks_afterupload') is not null drop proc project_tasks_afterupload
go
CREATE proc project_tasks_afterupload
	@project_id int,
	@node_id int = null
as
begin

	if @node_id is not null
	begin
		declare @temp_project_id int; set @temp_project_id = -@node_id
		exec project_tasks_afterupload @project_id = @temp_project_id
		
		update projects_tasks set parent_id = @node_id where project_id = @temp_project_id and parent_id is null
		update projects_tasks set project_id = @project_id where project_id = @temp_project_id
		update projects_tasks_links set project_id = @project_id where project_id = @temp_project_id
		
		-- mark node		
		update projects_tasks set is_node = 1 where project_id = @project_id and task_id = @node_id

		-- reorder
		exec project_tasks_reorder @project_id = @project_id
	end

	else
	begin
		-- parent_id
		update t
		set parent_id = t2.task_id
		from projects_tasks t
			left join projects_tasks t2 on t2.project_id = t.project_id and t2.task_number = t.parent_id
		where t.project_id = @project_id

		-- calc link (by predecessors)
		exec project_tasks_calc_links @project_id = @project_id

		-- reorder
		exec project_tasks_reorder @project_id = @project_id, @calctree = 1
	end

	-- calc has_childs
	update p
	set has_childs = 
			case 
				when exists(select 1 from projects_tasks where project_id = @project_id and parent_id = p.task_id and is_deleted = 0) 
				then 1 
			else 0 end
	from projects_tasks p
	where project_id = @project_id

end
GO
