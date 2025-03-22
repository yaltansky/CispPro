if object_id('project_task_move') is not null drop procedure project_task_move
go
create procedure project_task_move
	@mol_id int,
    @task_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  
	declare @project_id int = (select project_id from projects_tasks where task_id = @task_id)
	declare @where_rows varchar(100) = 'project_id = ' + cast(@project_id as varchar)

	exec tree_move_node 
		@mol_id = @mol_id,
        @table_name = 'projects_tasks',
		@key_name = 'task_id',
		@where_rows = @where_rows,
		@source_id = @task_id,
		@target_id = @target_id,
		@where = @where

end
go
