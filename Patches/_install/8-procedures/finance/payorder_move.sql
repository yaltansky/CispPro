if object_id('payorder_move') is not null drop procedure payorder_move
go
create procedure payorder_move
	@payorder_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	if @where = 'into' set @where = 'first'

	exec tree_move_node 
		@table_name = 'payorders',
		@key_name = 'payorder_id',
		@source_id = @payorder_id,
		@target_id = @target_id,
		@where = @where

end
go
