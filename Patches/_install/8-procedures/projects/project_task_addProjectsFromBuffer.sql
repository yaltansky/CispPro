if object_id('project_task_addProjectsFromBuffer') is not null
	drop procedure project_task_addProjectsFromBuffer
go
create procedure project_task_addProjectsFromBuffer
	@mol_id int,
	@task_id int
AS  
begin  

	declare @project_id int = (select project_id from projects_tasks where task_id = @task_id)
	declare @folder_id int = dbo.objs_buffer_id(@mol_id)

	declare @projects table(project_id int primary key, name varchar(200))
		insert into @projects(project_id, name)
		select distinct p.project_id, p.name
		from objs_folders_details od
			join projects p on p.project_id = od.obj_id
		where od.folder_id = @folder_id
			and od.obj_type in ('prj', 'dl')
	
	if exists(select 1 from @projects)
	begin
		if exists(
			select 1 from @projects p
			where exists(select 1 from projects_tasks where ref_project_id = p.project_id and is_deleted = 0)
			)
		begin
			raiserror('Один или несколько проектов/сделок из буфера уже включены в проект(ы).', 16, 1)
			return
		end

		insert into projects_tasks(project_id, parent_id, name, ref_project_id)
		select @project_id, @task_id, name, project_id from @projects

		update projects_tasks set has_childs = 1 where task_id = @task_id

		update x
		set program_id = @project_id
		from deals x
			join @projects p on p.project_id = x.deal_id

		exec project_tasks_refresh @project_id = @project_id
	end
end
go
