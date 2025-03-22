if object_id('budget_calc_node') is not null drop proc budget_calc_node
go
create proc budget_calc_node
	@budget_id int,
	@goal_account_id int = null,
	@node_id int = null,
	@budget_period_id int = null
as
begin

	set nocount on;

-- @nodes
	if @node_id is not null
	begin
		declare @nodes table(node hierarchyid)
		declare @node hierarchyid = (select node from bdr_articles where node_id = @node_id)
		
		insert into @nodes(node)
		select node from bdr_articles where @node.IsDescendantOf(node) = 1

		-- update tree's attributes
		update x
		set node = a.node, has_childs = a.has_childs
		from budgets_plans x
			join bdr_articles a on a.article_id = x.article_id
		where x.budget_id = @budget_id
			and x.goal_account_id = @goal_account_id
			and x.node is null

	-- insert parents (if any)
		insert into budgets_plans(budget_id, goal_account_id, article_id, budget_period_id, node, has_childs)
		select @budget_id, @goal_account_id, article_id, @budget_period_id, node, has_childs
		from bdr_articles a
		where node in (select node from @nodes)
			and not exists(
				select 1 from budgets_plans 
				where budget_id = @budget_id 
					and goal_account_id = @goal_account_id
					and article_id = a.article_id 
					and budget_period_id = @budget_period_id
				)
	end

	-- нормализация плана по всем периодам и статьям
	else begin

		-- @rows
		declare @rows table(budget_period_id int, goal_account_id int, article_id int)
			insert into @rows(budget_period_id, goal_account_id, article_id)
			select distinct p.budget_period_id, p.goal_account_id, a.article_id
			from budgets_plans p
				join bdr_articles a on a.article_id = p.article_id
			where p.budget_id = @budget_id
				and (abs(p.plan_rur) >= 0.01 or abs(p.fact_rur_goal) >= 0.01)
				and a.has_childs = 0	

		-- @articles
		declare @articles table(goal_account_id int, article_id int, name varchar(250), node hierarchyid, has_childs bit)
			insert into @articles
			select distinct r.goal_account_id, a.article_id, a.name, a.node, a.has_childs
			from @rows r
				join bdr_articles a on a.article_id = r.article_id

			-- + parents
			insert into @articles(goal_account_id, article_id, name, node, has_childs)
			select distinct aa.goal_account_id, a.article_id, a.name, a.node, a.has_childs
			from bdr_articles a, @articles aa
			where aa.node.IsDescendantOf(a.node) = 1

		-- @periods
		declare @periods table(budget_period_id int)
			insert into @periods(budget_period_id)
			select distinct budget_period_id from @rows

		-- append parents (if any)
		insert into budgets_plans(budget_id, goal_account_id, article_id, budget_period_id, node, has_childs)
		select distinct @budget_id, a.goal_account_id, a.article_id, per.budget_period_id, a.node, a.has_childs
		from @articles a, @periods per
		where not exists(
			select 1 from budgets_plans 
			where budget_id = @budget_id 
				and goal_account_id = a.goal_account_id
				and article_id = a.article_id 
				and budget_period_id = per.budget_period_id
			)
	end

-- update totals
	update x
	set plan_rur = 0
	from budgets_plans x
	where x.budget_id = @budget_id
		and (@goal_account_id is null or x.goal_account_id = @goal_account_id)
		and (@node_id is null or x.node in (select node from @nodes))
		and (@budget_period_id is null or x.budget_period_id = @budget_period_id)
		and has_childs = 1

	update x
	set plan_rur = r.plan_rur
	from budgets_plans x
		join (
			select y2.id, 
				sum(y1.plan_rur) as plan_rur
			from budgets_plans y1
				cross apply budgets_plans y2
			where y1.budget_id = y2.budget_id
				and y1.goal_account_id = y2.goal_account_id
				and y1.budget_period_id = y2.budget_period_id
				and y1.node.IsDescendantOf(y2.node) = 1
				and y1.has_childs = 0
				and y2.has_childs = 1
			group by y2.id
		) r on r.id = x.id
	where x.budget_id = @budget_id
		and (@goal_account_id is null or x.goal_account_id = @goal_account_id)
		and (@node_id is null or x.node in (select node from @nodes))
		and (@budget_period_id is null or x.budget_period_id = @budget_period_id)

end
GO
