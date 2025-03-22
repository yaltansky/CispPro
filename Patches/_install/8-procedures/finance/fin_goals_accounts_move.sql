if object_id('fin_goals_accounts_move') is not null drop proc fin_goals_accounts_move
go
create procedure fin_goals_accounts_move
	@goal_account_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	exec tree_move_node 
		@table_name = 'fin_goals_accounts',
		@key_name = 'goal_account_id',
		@source_id = @goal_account_id,
		@target_id = @target_id,
		@where = @where
	
end
GO
