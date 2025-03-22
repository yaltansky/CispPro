if object_id('fin_goal_details_view') is not null drop procedure fin_goal_details_view
go
create proc fin_goal_details_view
	@mol_id int,
	@fin_goal_id int,
	@fin_goal_sum_id int,
	@search varchar(50) = null
as
begin
	
	set nocount on;
	
	declare @group_id varchar(32), @goal_account_id int, @budget_id int, @article_id int, @node hierarchyid
	select 
		@group_id = group_id,
		@goal_account_id = goal_account_id,
		@budget_id = budget_id,
		@article_id = article_id,
		@node = node
	from fin_goals_sums
	where fin_goal_id = @fin_goal_id
		and id = @fin_goal_sum_id

	declare @has_folders bit = case when @group_id = 'budgets_by_vendors' then 1 else 0 end

	create table #nodes(node_id int primary key, folder_id int, goal_account_id int, budget_id int, article_id int)

		insert into #nodes
		select distinct node_id, folder_id, goal_account_id, budget_id, article_id
		from fin_goals_sums
		where fin_goal_id = @fin_goal_id 
			and mol_id = @mol_id 
			and group_id = @group_id
			and node.IsDescendantOf(@node) = 1
			and has_childs = 0

	create table #result(
		goal_account_id int, budget_id int, article_id int,
		parent_id int, 
		node_id int index ix_node,
		name varchar(250), node hierarchyid, has_childs bit,
		value_start decimal(18, 2),
		value_in decimal(18, 2),
		value_out decimal(18, 2),
		value_end decimal(18, 2)
		)
	
	if @search is not null set @search = '%' + @search + '%'

-- build tree
	if @group_id = 'bdr_articles'
	begin
		insert into #result(goal_account_id, budget_id, node_id, name, node, has_childs, value_start, value_in, value_out, value_end)
		select
			@goal_account_id, a.budget_id, a.budget_id, a.name, null, 0 as has_childs,
			sum(f.value_start) as value_start, 
			sum(f.value_in) as value_in, 
			sum(f.value_out) as value_out, 
			sum(f.value_end) as value_end 			
		from fin_goals_details f
			join budgets a on a.budget_id = f.budget_id
		where f.fin_goal_id = @fin_goal_id
			and f.mol_id = @mol_id				
			and (@has_folders = 0 or f.folder_id in (select folder_id from #nodes))
			and f.article_id in (select article_id from #nodes where article_id is not null)
			and (@search is null or a.name like @search)
		group by a.budget_id, a.name
	end

	else begin
		;with tree as (
			select
				a.parent_id, a.article_id as node_id, a.name, a.node, 0 as has_childs,
				sum(f.value_start) as value_start, 
				sum(f.value_in) as value_in, 
				sum(f.value_out) as value_out, 
				sum(f.value_end) as value_end 			
			from fin_goals_details f
				join bdr_articles a on a.article_id = f.article_id
			where f.fin_goal_id = @fin_goal_id
				and f.mol_id = @mol_id
				and (@has_folders = 0 or f.folder_id in (select folder_id from #nodes))
				and (
						(@group_id like 'budgets%' and f.budget_id in (select budget_id from #nodes where budget_id is not null))
					or	(@group_id = 'fin_goals_accounts'  and f.GOAL_ACCOUNT_ID in (select goal_account_id from #nodes where goal_account_id is not null))
					)
				and (@search is null or a.name like @search)
			group by a.parent_id, a.article_id, a.name, a.node

			union all
			select t.parent_id, t.article_id, t.name, t.node, 1, null, null, null, null
			from bdr_articles t
				join tree on tree.parent_id = t.article_id
		)
		insert into #result(goal_account_id, budget_id, article_id, parent_id, node_id, name, node, has_childs, value_start, value_in, value_out, value_end)
		select distinct @goal_account_id, @budget_id, node_id, parent_id, node_id, name, node, has_childs, value_start, value_in, value_out, value_end
		from tree
	end

	update x
	set value_start = r.value_start,
		value_in = r.value_in,
		value_out = r.value_out,
		value_end = isnull(r.value_start,0) + isnull(r.value_in,0) + isnull(r.value_out,0)
	from #result x
		join (
			select y2.node_id, 
				sum(y1.value_start) as value_start,
				sum(y1.value_in) as value_in,
				sum(y1.value_out) as value_out,
				sum(y1.value_end) as value_end
			from #result y1
				cross apply #result y2
			where (y2.has_childs = 1 and y1.has_childs = 0)
				and y1.node.IsDescendantOf(y2.node) = 1
			group by y2.node_id
		) r on r.node_id = x.node_id

	delete from fin_goals_sums_details where fin_goal_id = @fin_goal_id and mol_id = @mol_id

	insert into fin_goals_sums_details (
		mol_id, fin_goal_id, fin_goal_sum_id, 
		goal_account_id, budget_id, article_id,
		node_id, name, node, parent_id, has_childs, level_id, 
		value_start,
		value_in,
		value_out,
		value_end
		)
	select
		@mol_id,
		@fin_goal_id,
		@fin_goal_sum_id,
		goal_account_id, budget_id, article_id,
		node_id, name, node, parent_id, has_childs, node.GetLevel(),
        --
		value_start,
		value_in,
		value_out,
		value_end
	from #result

	drop table #nodes, #result

	select * from fin_goals_sums_details where fin_goal_id = @fin_goal_id and mol_id = @mol_id
	order by node

end
go
