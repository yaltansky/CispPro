if object_id('project_result_move') is not null drop procedure project_result_move
go
create procedure project_result_move
	@result_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	declare @project_id int = (select project_id from projects_results where result_id = @result_id)
	declare @where_rows varchar(100) = 'project_id = ' + cast(@project_id as varchar)

	exec tree_move_node 
		@table_name = 'projects_results',
		@key_name = 'result_id',
		@where_rows = @where_rows,
		@source_id = @result_id,
		@target_id = @target_id,
		@where = @where

end
go
