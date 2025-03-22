if object_id('budget_view_wbs') is not null drop proc budget_view_wbs
go
-- budget_view_wbs 700, 273, @article_id = 76, @budget_period_id = 144
create proc budget_view_wbs
	@mol_id int,
	@budget_id int,	
	@article_id int = null,
	@budget_period_id int = null,
	@findoc_id int = null,
	@search varchar(50) = null,
	@extra_id int = null	
as
begin

	set nocount on;

	declare @project_id int = (select project_id from budgets where budget_id = @budget_id)
	
	create table #result (task_id int primary key, node hierarchyid)

	-- tasks
	insert into #result(task_id, node)
	select task_id, node
	from projects_tasks pp
	where project_id = @project_id
		and pp.is_deleted = 0
			
		-- @search
		and (@search is null or pp.name like '%' + @search + '%')
			
		-- @extra_id
		and (
			@extra_id is null
			-- { id: 1, name: 'Запланировано' },
			or @extra_id = 1 and exists(
				select 1 from v_projects_tasks_budgets 
				where task_id = pp.task_id 
					and (@article_id is null or article_id = @article_id)
				)
			)
			
		and pp.task_id in (
			select task_id from v_projects_tasks_budgets where project_id = @project_id
				and (@article_id is null or article_id = @article_id)
			)

	-- + parents
	insert into #result(task_id, node)
		select distinct pt.task_id, pt.node
		from projects_tasks pt
			join #result r on r.node.IsDescendantOf(pt.node) = 1	
		where pt.project_id = @project_id
			and not exists(select 1 from #result where task_id = pt.task_id)
			and pt.is_deleted = 0

-- budget access
	declare @access_budget bit
	exec budget_check_access @mol_id = @mol_id, @budget_id = @budget_id, @accesstype = 'read', @allowaccess = @access_budget out

-- calc subtotals
	create table #budget (		
		project_id int,
		parent_id int, task_id int, task_number int, ref_budget_id int,
		name varchar(250), d_from datetime, d_to datetime,
		node hierarchyid, has_childs bit, outline_level int,
		article_id int, budget_value decimal(18,2), budget_value_fact decimal(18,2), budget_value_bind decimal(18,2),
		has_details bit,
		d_doc datetime, note varchar(max)
		)
		create index ix_budgets_nodes on #budget(node)
	
	insert into #budget (
		project_id, parent_id, task_id, task_number, name, d_from, d_to, node, has_childs, outline_level, article_id,
		d_doc, budget_value, budget_value_fact, budget_value_bind,
		has_details
		)
	select
		x.project_id, x.parent_id, x.task_id, x.task_number, x.name, x.d_from, x.d_to,
		x.node, x.has_childs, x.outline_level,
		@article_id,		
		ba.d_doc_calc,
		-- budget_value
		case
			when @access_budget = 1 then ba.article_value
		end,
		-- budget_value_fact
		case when @access_budget = 1 then 
			(
			select sum(value_bind) as value_bind
			from findocs_wbs
			where task_id = x.task_id
				and budget_id = @budget_id
				and (@article_id is null or article_id = @article_id)
			)
		end,
		-- budget_value_bind
		case when @access_budget = 1 then 
			(
			select sum(value_bind) as value_bind
			from findocs_wbs
			where task_id = x.task_id
				and budget_id = @budget_id
				and article_id = @article_id
				and findoc_id = @findoc_id
			)
		end,
		ba.has_details
	from projects_tasks x
		left join (
			select task_id, 
				max(d_doc_calc) as d_doc_calc,
				sum(plan_dds) as article_value,
				max(cast(has_details as int)) as has_details
			from v_projects_tasks_budgets
			where budget_id = @budget_id
				and (@article_id is null or article_id = @article_id)
				and (@budget_period_id is null or budget_period_id = @budget_period_id)
			group by task_id
		) ba on ba.task_id = x.task_id
	where x.project_id = @project_id
		and x.task_id in (select task_id from #result)

	update x
	set budget_value = (select sum(budget_value) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),
		budget_value_fact = (select sum(budget_value_fact) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0),
		budget_value_bind = (select sum(budget_value_bind) from #budget where node.IsDescendantOf(x.node) = 1 and has_childs = 0)
	from #budget x
	where has_childs = 1

	update x
	set note = tb.note
	from #budget x
		inner join v_projects_tasks_budgets tb on tb.budget_id = @budget_id and tb.task_id = x.task_id and tb.article_id = x.article_id
	where tb.has_details = 0

	update x
	set ref_budget_id = b.budget_id
	from #budget x
		inner join projects_tasks pt on pt.task_id = x.task_id
			inner join budgets b on b.project_id = pt.ref_project_id

-- final select
	select * from #budget
		--where abs(budget_value) > 0
	order by task_number

end
go
