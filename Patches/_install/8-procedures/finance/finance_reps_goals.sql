if object_id('finance_reps_goals') is not null drop proc finance_reps_goals
go
-- exec finance_reps_goals 700, 8161
create proc finance_reps_goals
	@mol_id int,
	@fin_goal_id int
as
begin

	set nocount on;

	select
		a1 = up2.name,
		a2 = up1.name,
		a3 = ga.name,
		budget_name = b.name,
		article_name = a.name,
		x.value_start,
		x.value_in,
		x.value_out,
		value_diff = x.value_in + x.value_out,
		x.value_end
	from fin_goals_details x
		left join fin_goals_accounts ga on ga.goal_account_id = x.goal_account_id
			left join fin_goals_accounts up1 on up1.goal_account_id = ga.parent_id
				left join fin_goals_accounts up2 on up2.goal_account_id = up1.parent_id
		left join budgets b on b.budget_id = x.budget_id
		left join bdr_articles a on a.article_id = x.article_id
	where x.fin_goal_id = @fin_goal_id
		and x.mol_id = @mol_id
end
go
