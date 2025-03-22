if object_id('depts_node_move') is not null drop procedure depts_node_move
go
create procedure depts_node_move
	@dept_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	if @where = 'into' set @where = 'first'

	exec tree_move_node 
		@table_name = 'depts',
		@key_name = 'dept_id',
		@source_id = @dept_id,
		@target_id = @target_id,
		@where = @where

	exec depts_calc

end
go
