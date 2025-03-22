if object_id('project_risk_move') is not null
	drop procedure project_risk_move
go
create procedure project_risk_move
	@risk_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	declare @project_id int = (select project_id from projects_risks where risk_id = @risk_id)
	declare @where_rows varchar(100) = 'project_id = ' + cast(@project_id as varchar)

	exec tree_move_node 
		@table_name = 'projects_risks',
		@key_name = 'risk_id',
		@where_rows = @where_rows,
		@source_id = @risk_id,
		@target_id = @target_id,
		@where = @where

end
go
