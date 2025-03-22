if object_id('findocs_accounts_move') is not null drop procedure findocs_accounts_move
go
create procedure findocs_accounts_move
	@account_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	if @where = 'into' set @where = 'first'

	exec tree_move_node 
		@table_name = 'findocs_accounts',
		@key_name = 'account_id',
		@source_id = @account_id,
		@target_id = @target_id,
		@where = @where

end
go
