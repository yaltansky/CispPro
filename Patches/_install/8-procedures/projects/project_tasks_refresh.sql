if object_id('project_tasks_refresh') is not null drop proc project_tasks_refresh
go
create proc project_tasks_refresh @project_id int as
	exec project_tasks_reorder @project_id = @project_id, @calctree = 1
go