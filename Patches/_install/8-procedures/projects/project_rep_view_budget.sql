if exists(select 1 from sys.objects where name = 'project_rep_view_budget')
	drop proc project_rep_view_budget
go
create proc project_rep_view_budget
	@mol_id int,
	@report_id int
as
begin

	set nocount on;

	declare @project_id int = (select project_id from projects_reps where rep_id = @report_id)
	declare @budget_id int = (select max(budget_id) from budgets where project_id = @project_id and is_deleted = 0)
	
	declare @result table(article_id int primary key, node hierarchyid)

	-- articles
	insert into @result(article_id, node)
	select distinct a.article_id, a.node
	from projects_reps_budgets b
		inner join bdr_articles a on a.article_id = b.article_id
	where b.rep_id = @report_id

	-- + parents
	insert into @result(article_id, node)
		select distinct a.article_id, a.node
		from bdr_articles a
			join @result r on r.node.IsDescendantOf(a.node) = 1	
		where a.article_id not in (select article_id from @result)

-- budget access
	declare @access_budget bit
	exec budget_check_access @mol_id = @mol_id, @budget_id = @budget_id, @accesstype = 'read', @allowaccess = @access_budget out

-- calc subtotals
	create table #budget (		
		article_id int, name varchar(250),
		parent_id int, node hierarchyid, has_childs bit, level_id int,
		plan_bds_total decimal(18,2),
		plan_bds_in decimal(18,2),
		fact_bds_in decimal(18,2),
		fact_bds_in2 decimal(18,2),
		plan_bds decimal(18,2),
		fact_bds decimal(18,2),
		fact_bds2 decimal(18,2),
		fact_bds_out decimal(18,2),
		fact_bds_out2 decimal(18,2)
		)
		create index ix_budgets_nodes on #budget(node)
	
	insert into #budget (article_id, name, parent_id, node, has_childs, level_id)
	select article_id, name, parent_id, node, has_childs, level_id
	from bdr_articles
	where article_id in (select article_id from @result)

	update x
	set plan_bds_total = (select sum(plan_bds) from projects_reps_budgets where article_id = x.article_id),
		--
		plan_bds_in = (select sum(plan_bds) from projects_reps_budgets where article_id = x.article_id and inout = -1),
		fact_bds_in = (select sum(fact_bds) from projects_reps_budgets_pays where article_id = x.article_id and plan_inout = -1 and fact_inout = -1),
		fact_bds_in2 = (select sum(fact_bds) from projects_reps_budgets_pays where article_id = x.article_id and plan_inout = -1 and fact_inout <> -1),
		--
		plan_bds = (select sum(plan_bds) from projects_reps_budgets where article_id = x.article_id and inout = 0),
		fact_bds = (select sum(fact_bds) from projects_reps_budgets_pays where article_id = x.article_id and plan_inout = 0 and fact_inout = 0),
		fact_bds2 = (select sum(fact_bds) from projects_reps_budgets_pays where article_id = x.article_id and plan_inout = 0 and fact_inout <> 0),
		--
		fact_bds_out = (select sum(fact_bds) from projects_reps_budgets_pays where article_id = x.article_id and plan_inout = 1 and fact_inout = 1),
		fact_bds_out2 = (select sum(fact_bds) from projects_reps_budgets_pays where article_id = x.article_id and plan_inout = 1 and fact_inout <> 1)
	from #budget x
	where has_childs = 0

	update x
	set plan_bds_total = (select sum(plan_bds_total) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),
		plan_bds_in = (select sum(plan_bds_in) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),
		fact_bds_in = (select sum(fact_bds_in) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),
		fact_bds_in2 = (select sum(fact_bds_in2) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),
		plan_bds = (select sum(plan_bds) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),
		fact_bds = 
			nullif(
				isnull((select sum(fact_bds) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),0)
				+ isnull((select sum(fact_bds_out) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),0)
				+ isnull((select sum(fact_bds_out2) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),0),
				0),
		fact_bds2 = (select sum(fact_bds2) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0)
	from #budget x
	where has_childs = 1

-- final select
	select * from #budget
	order by node

end
go
