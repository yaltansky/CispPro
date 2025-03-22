if object_id('project_task_toggle') is not null drop procedure project_task_toggle
go
create procedure project_task_toggle
	@mol_id int,
    @task_id int,
	@is_deleted bit = null
AS  
begin  

	declare @project_id int, @node hierarchyid
	select 
		@project_id = project_id, 
		@node = node,
		@is_deleted = isnull(@is_deleted, case when isnull(is_deleted,0) = 1 then 0 else 1 end)
	from projects_tasks where task_id = @task_id
	
	declare @tasks as app_pkids

	update projects_tasks set 
        is_deleted = @is_deleted,
        update_date = getdate(),
        update_mol_id = @mol_id
	output inserted.task_id into @tasks
	where project_id = @project_id
		and node.IsDescendantOf(@node) = 1

	if exists(
		select 1 from projects_tasks
		where task_id in (select id from @tasks)
			and ref_project_id is not null
		)
	begin
		update x
		set parent_id = case when t.is_deleted = 1 then null else t.project_id end,
            update_date = getdate(),
            update_mol_id = @mol_id
		from projects x
			join projects_tasks t on t.ref_project_id = x.project_id
				join @tasks i on i.id = t.task_id
	end

end
go
