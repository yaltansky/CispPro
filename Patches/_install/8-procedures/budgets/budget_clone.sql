if object_id('budget_clone') is not null drop proc budget_clone
go
-- exec budget_clone 446
create proc budget_clone
	@budget_id int
as
begin
	
	set nocount on;

	insert into budgets(
		name, status_id, note, project_id, add_date, mol_id, main_id, is_wbs, update_mol_id, update_date, content, inherited_access, type_id, subject_id, period_id
	)
	select
		name + ' (копия)', 0, note, project_id, add_date, mol_id, main_id, is_wbs, update_mol_id, update_date, content, inherited_access, type_id, subject_id, period_id
	from budgets
	where budget_id = @budget_id

	declare @new_id int = @@identity

	-- BUDGETS_GOALS
	insert into budgets_goals(budget_id, goal_account_id)
	select @new_id, goal_account_id
	from budgets_goals
	where budget_id = @budget_id

	-- BUDGETS_PERIODS
	insert into budgets_periods(
		budget_id, bdr_period_id, name, date_start, date_end, is_deleted, is_selected, is_fixed
		)
	select @new_id, bdr_period_id, name, date_start, date_end, is_deleted, is_selected, is_fixed
	from budgets_periods
	where budget_id = @budget_id

	-- BUDGETS_PLANS
	insert into budgets_plans(
		budget_id, goal_account_id, article_id, budget_period_id, plan_rur, node, has_childs, fact_rur_goal
		)
	select 
		@new_id, goal_account_id, article_id, per2.budget_period_id, x.plan_rur, x.node, x.has_childs, x.fact_rur_goal
	from budgets_plans x
		join budgets_periods per1 on per1.budget_id = @budget_id and per1.budget_period_id = x.budget_period_id
			join budgets_periods per2 on per2.budget_id = @new_id and per2.name = per1.name
	where x.budget_id = @budget_id
	
	-- BUDGETS_TOTALS
	insert into budgets_totals(
		budget_id, goal_account_id, article_id, plan_bdr, plan_dds, plan_dds_current, fact_dds, fact_dds_goal, name, node, parent_id, has_childs, sort_id, level_id, is_deleted, node_priority, plan_dds_detailed, fact_dds_self, fact_dds_ext
		)
	select 
		@new_id, goal_account_id, article_id, plan_bdr, plan_dds, plan_dds_current, fact_dds, fact_dds_goal, name, node, parent_id, has_childs, sort_id, level_id, is_deleted, node_priority, plan_dds_detailed, fact_dds_self, fact_dds_ext
	from budgets_totals
	where budget_id = @budget_id

	update budgets set status_id = 2 where budget_id = @budget_id
end
go
