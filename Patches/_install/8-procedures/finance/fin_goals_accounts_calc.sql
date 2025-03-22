if object_id('fin_goals_accounts_calc') is not null	drop proc fin_goals_accounts_calc
go
create proc fin_goals_accounts_calc
as
begin

	exec tree_calc_nodes 'fin_goals_accounts', 'goal_account_id'

end
GO
