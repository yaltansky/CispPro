if object_id('project_rep_view_budget_wbs') is not null drop proc project_rep_view_budget_wbs
go
create proc project_rep_view_budget_wbs
	@mol_id int,
	@report_id int,
	@article_id int = null,
	@inout int = null,
	@search varchar(50) = null
as
begin

	set nocount on;

	declare @project_id int = (select project_id from projects_reps where rep_id = @report_id)
	declare @budget_id int = (select budget_id from budgets where project_id = @project_id and is_deleted = 0)
	
-- search (if any)
	declare @result table(task_id int primary key, node hierarchyid)

	-- childs tasks
	insert into @result(task_id, node)
	select task_id, node
	from projects_tasks pp
	where project_id = @project_id
		and task_id in (
				select task_id from projects_reps_budgets
				where rep_id = @report_id 
					and abs(plan_bds) > 0
					and (@article_id is null or article_id = @article_id)
					and (@inout is null or inout = @inout)
				)
		and (@search is null or pp.name like '%' + @search + '%')

	-- + parents
	insert into @result(task_id, node)
		select distinct pt.task_id, pt.node
		from projects_tasks pt
			join @result r on r.node.IsDescendantOf(pt.node) = 1	
		where pt.project_id = @project_id
			and not exists(select 1 from @result where task_id = pt.task_id)

-- budget access
	declare @access_budget bit
	exec budget_check_access @mol_id = @mol_id, @budget_id = @budget_id, @accesstype = 'read', @allowaccess = @access_budget out

-- calc subtotals
	create table #budget (		
		project_id int,
		parent_id int, task_id int, task_number int, name varchar(250),
		node hierarchyid, has_childs bit,
		plan_bds decimal(18,2)
		)
		create index ix_budgets_nodes on #budget(node)
	
	insert into #budget (
		project_id, task_id, task_number, name,
		parent_id, node, has_childs,
		plan_bds
		)
	select
		x.project_id, x.task_id, x.task_number, x.name,
		x.parent_id, x.node, x.has_childs,
		ba.plan_bds
	from projects_tasks x
		left join (
			select task_id, 
				sum(plan_bds) as plan_bds
			from projects_reps_budgets
			where budget_id = @budget_id
				and (@article_id is null or article_id = @article_id)
				and (@inout is null or inout = @inout)
			group by task_id
		) ba on ba.task_id = x.task_id
	where x.project_id = @project_id
		and x.task_id in (select task_id from @result)
		and @access_budget = 1
		
	update x
	set plan_bds = (select sum(plan_bds) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0)
	from #budget x
	where has_childs = 1

-- final select
	select * from #budget
	order by task_number

end
go
