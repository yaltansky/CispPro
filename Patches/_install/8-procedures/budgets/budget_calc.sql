if object_id('budget_calc') is not null drop proc budget_calc
go
-- exec budget_calc 446
create proc budget_calc
	@budget_id int,
	@ifnoexists bit = 0,
	@trace bit = 0
as
begin
	
	set nocount on;
		
	if @ifnoexists = 1 and exists(select 1 from budgets_totals where budget_id = @budget_id)
		return -- nothing todo

	-- deal_calc
	declare @deal_id int = (select top 1 deal_id from deals where budget_id = @budget_id)
	if @deal_id is not null and not exists(select 1 from deals_budgets where deal_id = @deal_id)
		exec deal_calc @deal_id = @deal_id

	declare @tid int; exec tracer_init 'budget_calc', @trace_id = @tid out

	declare @project_id int = (select top 1 project_id from budgets where budget_id = @budget_id)	

	-- #ref_projects
	create table #ref_projects (project_id int primary key, task_id int);
		insert into #ref_projects
			select ref_project_id, task_id from projects_tasks
			where project_id = @project_id and ref_project_id is not null

	if @project_id is not null and @trace = 1
	begin		
		if exists(select 1 from #ref_projects)
		begin
			print 'ВНИМАНИЕ: проект ' + cast(@project_id as varchar) + ' является агрегатором и его бюджет определяется дочерними бюджетами.'
			select * from #ref_projects
		end
	end

exec tracer_log @tid, 'BUDGETS_PLANS_WBS'
	exec budget_calc;10 @budget_id = @budget_id, @tid = @tid
	
exec tracer_log @tid, 'BUDGETS_TOTALS: PLAN_DDS, PLAN_DDS_CURRENT, PLAN_DDS_DETAILED'
	exec budget_calc;20 @budget_id = @budget_id

exec tracer_log @tid, 'BUDGETS_TOTALS: FACT_DDS, FACT_DDS_SELF'
	exec budget_calc;30 @budget_id = @budget_id

exec tracer_log @tid, 'BUDGETS_TOTALS: FACT_DDS_GOAL, FACT_RUR_GOAL'
	exec budget_calc;40 @budget_id = @budget_id

exec tracer_log @tid, 'totals (hierarchy)'
	exec budget_calc;50 @budget_id = @budget_id

	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid
	
end
go
-- BUDGETS_PLANS: from WBS or DEALS_BUDGETS
create proc budget_calc;10
	@budget_id int,
	@tid int
as
begin
	
	declare @today datetime = dbo.today()

	-- clear is_wbs flag
	update budgets set is_wbs = 0 where budget_id = @budget_id

	declare @project_id int = (select top 1 project_id from budgets where budget_id = @budget_id)

	-- delete tasks marked as deleted
	delete from projects_tasks where project_id = @project_id and is_deleted = 1
	
	-- delete empty rows
	delete from projects_tasks_budgets
	where project_id = @project_id
		and ( 
				(abs(isnull(plan_dds,0)) + abs(isnull(plan_bdr,0)) = 0) 
				or is_deleted = 1 
			)

	-- delete rows marked as deleted
	delete x 
	from projects_tasks_budgets_details x
		join projects_tasks_budgets b on b.id = x.parent_id
	where b.project_id = @project_id
		and x.is_deleted = 1

	-- delete rows for summary tasks
	delete from projects_tasks_budgets
	where project_id = @project_id
		and task_id in (select task_id from projects_tasks where project_id = @project_id and has_childs = 1)

exec tracer_log @tid, '    Авто-создание периодов'
	-- -- для сделки
	-- if exists(select 1 from deals where budget_id = @budget_id)
	-- begin
	-- 	if not exists(select 1 from budgets_periods where budget_id = @budget_id)
	-- 	begin
	-- 		declare @min_date datetime = '1900-01-01'
	-- 		insert into budgets_periods(budget_id, name, date_start, date_end, is_selected)
	-- 		values 
	-- 			(@budget_id, 'весь период', @min_date, '2100-01-01', 1)
	-- 	end
	-- end

	-- если нет периодов
	if not exists(select 1 from budgets_periods where budget_id = @budget_id)
	begin
		insert into budgets_periods(budget_id, name, date_start, date_end, is_selected)
		values (@budget_id, 'ALL', '2000-01-01', '2100-01-01', 1)
	end
		
exec tracer_log @tid, '    Расчёт WBS для подчинённых бюджетов'
	exec budget_calc;11 @budget_id = @budget_id, @tid = @tid
		
	if exists(select 1 from projects_tasks_budgets where project_id = @project_id)
	begin

exec tracer_log @tid, '    Трансформация WBS в BUDGETS_PLANS, BUDGETS_TOTALS'
		-- set is_wbs flag
		update budgets set is_wbs = 1 where budget_id = @budget_id 

		-- prepare projects_tasks_budgets
		create table #budget_wbs (
			id int, detail_id int,
			budget_id int, article_id int,
			date_type_id int, date_lag int, d_doc datetime, task_d_from datetime, task_d_to datetime, budget_period_id int,
			plan_bdr decimal(18,2), plan_dds decimal(18,2)
			)
			create index ix_budget_wbs on #budget_wbs(article_id)

		insert into #budget_wbs(
			id, detail_id,
			budget_id, article_id, 
			date_type_id, date_lag, d_doc, task_d_from, task_d_to,
			plan_bdr, plan_dds
			)
		select 
			x.id, x.detail_id,
			x.budget_id, x.article_id, 
			x.date_type_id, x.date_lag, x.d_doc, t.d_from, t.d_to, 
			x.plan_bdr, x.plan_dds
		from v_projects_tasks_budgets x
			join projects_tasks t on t.task_id = x.task_id
		where t.project_id = @project_id 
			and x.budget_id = @budget_id

--/***/ SELECT SUM(PLAN_DDS) FROM #BUDGET_WBS WHERE ARTICLE_ID = 79

exec tracer_log @tid, '    Учёт привязки к дате операции'
		update #budget_wbs
		set d_doc = 
				coalesce(
					d_doc,
					dbo.work_day_add(
						case
							when date_type_id = 1 then task_d_from
							else task_d_to
						end,
						isnull(date_lag,0)
					),
					@today
				)

exec tracer_log @tid, '    Перевод в период бюджета'
		update x
		set budget_period_id = per.budget_period_id
		from #budget_wbs x
			join budgets_periods per on per.budget_id = @budget_id and x.d_doc between per.date_start and per.date_end
		where per.is_selected = 1

exec tracer_log @tid, '    сохранить отчётный период'
		update x
		set d_doc_calc = xx.d_doc,
			budget_period_id = xx.budget_period_id
		from projects_tasks_budgets x
			join #budget_wbs xx on xx.id = x.id
		where xx.detail_id is null

		update x
		set d_doc_calc = xx.d_doc,
			budget_period_id = xx.budget_period_id
		from projects_tasks_budgets_details x
			join #budget_wbs xx on xx.detail_id = x.id

--/***/ SELECT * FROM #BUDGET_WBS WHERE ARTICLE_ID = 79 AND BUDGET_PERIOD_ID IS NULL
		delete from #budget_wbs where budget_period_id is null
--/***/ SELECT SUM(PLAN_DDS) FROM #BUDGET_WBS WHERE ARTICLE_ID = 79

exec tracer_log @tid, '        budgets_plans'
		delete from budgets_plans where budget_id = @budget_id;

		insert into budgets_plans(budget_id, article_id, budget_period_id, plan_rur)
		select budget_id, article_id, budget_period_id, sum(plan_dds)
		from #budget_wbs
		group by budget_id, article_id, budget_period_id

exec tracer_log @tid, '        budgets_totals'
		delete from budgets_totals where budget_id = @budget_id;

		insert into budgets_totals(budget_id, article_id, plan_bdr, plan_dds)
		select budget_id, article_id, sum(plan_bdr), sum(plan_dds)
		from #budget_wbs
		group by budget_id, article_id
		
-- /***/ SELECT SUM(PLAN_DDS) FROM BUDGETS_TOTALS WHERE BUDGET_ID = @BUDGET_ID AND ARTICLE_ID = 79

	-- check
		if exists(select 1 from v_projects_tasks_budgets where budget_id = @budget_id and budget_period_id is null)
		begin
			declare @chk_min_date datetime, @chk_max_date datetime
				select @chk_min_date = min(d_doc_calc), @chk_max_date = max(d_doc_calc)
				from v_projects_tasks_budgets where budget_id = @budget_id and budget_period_id is null			
			
			declare @error varchar(max) = concat(
					'Обратите внимание, что есть строки WBS, которые не попадают в отчётные переиоды бюджета: ',
					convert(varchar, @chk_min_date, 104),
					' ... ',
					convert(varchar, @chk_max_date, 104),
					'.'
				)

			raiserror(@error, 16, 1)
		end
	end
		
	-- Копирование бюджета сделки
	else if exists(select 1 from deals where budget_id = @budget_id)
	begin
		exec tracer_log @tid, '        Копирование бюджета сделки'

		delete from budgets_plans where budget_id = @budget_id;

		insert into budgets_plans(budget_id, article_id, budget_period_id, plan_rur)
		select d.budget_id, x.article_id, per.budget_period_id, sum(x.value_bds)
		from deals_budgets x
			join deals d on d.deal_id = x.deal_id
			join budgets_periods per on per.budget_id = @budget_id and isnull(x.task_date, @today) between per.date_start and per.date_end
		where d.budget_id = @budget_id
		group by d.budget_id, x.article_id, per.budget_period_id

		delete from budgets_totals where budget_id = @budget_id;

		insert into budgets_totals(budget_id, article_id, plan_bdr, plan_dds)
		select d.budget_id, x.article_id, sum(x.value_bdr), sum(x.value_bds)
		from deals_budgets x
			join deals d on d.deal_id = x.deal_id
		where d.budget_id = @budget_id
		group by d.budget_id, x.article_id

	end

exec tracer_log @tid, '        append articles'
	create table #articles(article_id int primary key)
	insert into #articles select distinct article_id from budgets_plans where budget_id = @budget_id
	if exists(select 1 from #articles) exec budget_article_add @budget_id = @budget_id

-- calc nodes
	exec budget_calc_node @budget_id = @budget_id
end
go
-- BUDGETS_PLANS: aggregate budgets from refs (tree)
create proc budget_calc;11
	@budget_id int,
	@tid int
as
begin

	declare @project_id int = (select top 1 project_id from budgets where budget_id = @budget_id)	

	if not exists(select 1 from #ref_projects)
		return -- nothing todo

--exec tracer_log @tid, '    make refs budgets as childs'
--	update x
--	set parent_id = xx.budget_id,
--		level_id = xx.level_id + 1
--	from budgets x
--		join #ref_projects refs on refs.project_id = x.project_id
--		join budgets xx on xx.budget_id = @budget_id

--	update budgets set has_childs = 1 where budget_id = @budget_id

exec tracer_log @tid, '    clear final budget WBS'
	delete from projects_tasks_budgets where project_id = @project_id

	create table #map(parent_id int, task_id int, article_id int)
    create index ix_map on #map(task_id, article_id)

exec tracer_log @tid, '    create #budgets'
	select 
		refs.task_id,
		b.article_id, 
		b.d_doc,
		b.date_type_id,
		b.date_lag,
		b.plan_bdr,
		b.plan_dds
	into #budgets
	from v_projects_tasks_budgets b
		join #ref_projects refs on refs.project_id = b.project_id

		create index ix_budgets on #budgets(task_id, article_id)

exec tracer_log @tid, '    calc #budgets.d_doc'
	declare @date datetime
	update b
	set @date =
			case
				when b.date_type_id = 1 then t.d_from
				else t.d_to
			end,
		d_doc = 
				case
					when isnull(b.date_lag,0) = 0 then @date
					else 
						-- TODO dbo.work_day_add(@date, b.date_lag)
						dateadd(d, b.date_lag, @date)
				end
	from #budgets b
		join projects_tasks t on t.task_id = b.task_id
	where b.d_doc is null

exec tracer_log @tid, '    projects_tasks_budgets'
	insert into projects_tasks_budgets(project_id, budget_id, task_id, article_id, d_doc, plan_bdr, plan_dds, note, mol_id)
		output inserted.id, inserted.task_id, inserted.article_id into #map
	select @project_id, @budget_id, task_id, article_id, min(d_doc), sum(plan_bdr), sum(plan_dds), 'сводный бюджет', -25
	from #budgets
	group by task_id, article_id

exec tracer_log @tid, '    projects_tasks_budgets_details'
	insert into projects_tasks_budgets_details(parent_id, d_doc, plan_bdr, plan_dds, note)
	select m.parent_id, b.d_doc, sum(plan_bdr), sum(plan_dds), 'сводный график'
	from #budgets b
		join #map m on m.task_id = b.task_id and m.article_id = b.article_id
	group by m.parent_id, b.d_doc

exec tracer_log @tid, '    calc HAS_DETAILS'
	declare @has_details bit
	update projects_tasks_budgets 
	set @has_details = 
			case
				when exists(select 1 from projects_tasks_budgets_details where parent_id = projects_tasks_budgets.id) then 1
				else 0
			end,
		has_details = @has_details,
		d_doc = case when @has_details = 0 then d_doc end
	where budget_id = @budget_id

end
go
-- BUDGETS_TOTALS: PLAN_DDS, PLAN_DDS_CURRENT, PLAN_DDS_DETAILED
create proc budget_calc;20
	@budget_id int
as
begin

	create table #articles(parent_id int, article_id int)

-- синхронизуем классификацию
	;with tree as (
		select parent_id, article_id from bdr_articles
		where article_id in (select article_id from budgets_articles where budget_id = @budget_id)
			and has_childs = 0

		union all
		select x.parent_id, x.article_id
		from bdr_articles x
			join tree on tree.parent_id = x.article_id
		)
		insert into #articles select distinct parent_id, article_id from tree

	;delete from budgets_articles where budget_id = @budget_id
	;insert into budgets_articles (budget_id, parent_id, article_id) select @budget_id, parent_id, article_id from #articles

-- budgets_plans
	update x
	set node = a.node, has_childs = a.has_childs
	from budgets_plans x
		join bdr_articles a on a.article_id = x.article_id
	where x.budget_id = @budget_id

	delete from budgets_plans
	where budget_id = @budget_id
		and article_id not in (select article_id from budgets_articles where budget_id = @budget_id)

-- budgets_totals
	create table #deleted(
		goal_account_id int,
		article_id int,
		plan_bdr decimal(18,2),		
		plan_dds decimal(18,2),
		node_priority int,
		fact_dds decimal(18,2),
		fact_dds_self decimal(18,2)
		)

-- сохранить терминалы
	delete from budgets_totals 
	output deleted.goal_account_id, deleted.article_id, deleted.plan_bdr, deleted.plan_dds, deleted.node_priority, deleted.fact_dds, deleted.fact_dds_self
	into #deleted
	where budget_id = @budget_id

	insert into budgets_totals(
		budget_id,
		goal_account_id,
		article_id, name, node, parent_id, has_childs, sort_id, level_id,
		plan_bdr, plan_dds, node_priority, fact_dds, fact_dds_self
		)
	select 
		@budget_id,		
		aa.goal_account_id,
		a.article_id, a.name, a.node, a.parent_id, a.has_childs, a.sort_id, a.level_id,
		old.plan_bdr, old.plan_dds, old.node_priority, old.fact_dds, old.fact_dds_self
	from (
			select budgets_articles.article_id, goal_account_id = isnull(budgets_goals.goal_account_id,0)
			from budgets_articles
				left join budgets_goals on budgets_goals.budget_id = budgets_articles.budget_id
			where budgets_articles.budget_id = @budget_id
		) aa
		join bdr_articles a on a.article_id = aa.article_id
		left join (
			select d.*
			from #deleted d
				join bdr_articles aa on aa.article_id = d.article_id
			where aa.has_childs = 0
		) old on old.goal_account_id = aa.goal_account_id and old.article_id = aa.article_id

-- updates from BUDGETS_PLANS
	declare @today datetime = dbo.today()
	
	if exists(select 1 from budgets_periods where budget_id = @budget_id and is_selected = 1)
	begin
		declare @is_deal bit = case when exists(select 1 from deals where budget_id = @budget_id) then 1 end

		update x
		set plan_dds = y.plan_dds,
			plan_dds_detailed = y.plan_dds,
			plan_dds_current = case when @is_deal = 1 then y.plan_dds else y.plan_dds_current end
		from budgets_totals x
			left join (
				select 
					p.goal_account_id,
					p.article_id,				
					sum(p.plan_rur) as plan_dds,
					sum(case when per.date_end <= @today then p.plan_rur end) as plan_dds_current
				from budgets_plans p
					join budgets_periods per on per.budget_period_id = p.budget_period_id
				where p.budget_id = @budget_id
					and p.has_childs = 0
					and per.is_selected = 1
					and per.is_deleted = 0
				group by p.goal_account_id, p.article_id
			) y on y.goal_account_id = x.goal_account_id and y.article_id = x.article_id
		where x.budget_id = @budget_id
	end
end
go
-- BUDGETS_TOTALS: FACT_DDS, FACT_DDS_SELF
create proc budget_calc;30
	@budget_id int
as
begin

	if (select type_id from budgets where budget_id = @budget_id) = 4
	begin
		exec budget_calc;31 @budget_id = @budget_id
		return
	end

	declare @project_id int = (select top 1 project_id from budgets where budget_id = @budget_id)	

-- #ref_budgets
	create table #ref_budgets (budget_id int primary key);

	if exists(select 1 from #ref_projects)
		insert into #ref_budgets select budget_id from budgets
		where project_id in (select project_id from #ref_projects)
	
	if not exists(select 1 from #ref_budgets where budget_id = @budget_id)
		insert into #ref_budgets select @budget_id

	create table #fact(
		subject_id int index ix_subject, 
		agent_id int index ix_agent,
		article_id int index ix_article,
		fact_dds decimal(18,2), internal bit default(0))

	declare @subjects table(subject_id int)
	insert into @subjects select subject_id from budgets_subjects where budget_id = @budget_id
	if not exists(select 1 from @subjects) insert into @subjects select subject_id from subjects

	declare @from_date datetime = (select min(date_start) from budgets_periods where budget_id = @budget_id and is_selected = 1)
	declare @to_date datetime = (select max(date_end) from budgets_periods where budget_id = @budget_id and is_selected = 1)

	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

	-- #fact
	insert into #fact(subject_id, agent_id, article_id, fact_dds)
		select fd.subject_id, fd.agent_id, fd.article_id, sum(fd.value_rur) as value_rur
		from (
			select subject_id, agent_id, budget_id, article_id, value_rur
			from findocs#
			where subject_id in (select subject_id from @subjects)
				and d_doc between @from_date and @to_date
				and account_id not in (
						select account_id from findocs_accounts where name = @vat_refund
						)
			) fd		
			join bdr_articles a on a.article_id = fd.article_id
			join #ref_budgets ref on ref.budget_id = fd.budget_id
		group by fd.subject_id, fd.agent_id, fd.article_id
		having abs(sum(fd.value_rur)) >= 0.01

	-- internal
	update x
	set internal = 1
	from #fact x
		join subjects s on s.subject_id = x.subject_id
	where x.agent_id <> s.pred_id
		and x.agent_id in (select pred_id from subjects where pred_id is not null)

-- append articles
	create table #articles(article_id int)
	insert into #articles select distinct article_id from #fact

	if exists(select 1 from #articles)
		exec budget_article_add @budget_id = @budget_id

-- append budgets_totals with article_id
	insert into budgets_totals(budget_id, article_id)
	select distinct @budget_id, article_id
	from #fact f
	where not exists(select 1 from budgets_totals where budget_id = @budget_id and article_id = f.article_id)

-- update
	update budgets_totals set fact_dds = 0, fact_dds_self = 0 where budget_id = @budget_id

	update p
	set fact_dds = f.fact_dds,
		fact_dds_self = f1.fact_dds		
	from budgets_totals p
		join (
			select article_id, sum(fact_dds) as fact_dds
			from #fact group by article_id
		) f on f.article_id = p.article_id
		left join (
			select article_id, sum(fact_dds) as fact_dds
			from #fact where internal = 1 group by article_id
		) f1 on f1.article_id = p.article_id
	where p.budget_id = @budget_id

	-- budgets_totals_subjects
	delete from budgets_totals_subjects where budget_id = @budget_id

	insert into budgets_totals_subjects (budget_id, subject_id, value_left)
	select @budget_id, subject_id, sum(fact_dds)
	from #fact
	group by subject_id
end
go
-- BUDGETS_TOTALS: FACT_DDS (операционные бюджеты)
create proc budget_calc;31
	@budget_id int
as
begin

	create table #fact(
		goal_account_id int index ix_goal,
		article_id int index ix_article,
		fact_dds decimal(18,2)
		)

	declare @subject_id int = (select subject_id from budgets where budget_id = @budget_id)
	declare @from_date datetime = (select min(date_start) from budgets_periods where budget_id = @budget_id and is_selected = 1)
	declare @to_date datetime = (select max(date_end) from budgets_periods where budget_id = @budget_id and is_selected = 1)

	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

	-- #fact	
	insert into #fact(goal_account_id, article_id, fact_dds)
		select fd.goal_account_id, fd.article_id, sum(fd.value_rur) as value_rur
		from (
			select f.goal_account_id, f.article_id, f.value_rur
			from findocs# f
			where f.subject_id = @subject_id
				and f.d_doc between @from_date and @to_date
				and f.account_id not in (select account_id from findocs_accounts where name =  @vat_refund)
			) fd		
			join bdr_articles a on a.article_id = fd.article_id
		group by fd.goal_account_id, fd.article_id
		having abs(sum(fd.value_rur)) >= 0.01

-- append articles
	create table #articles(article_id int)
	insert into #articles select distinct article_id from #fact

	if exists(select 1 from #articles)
		exec budget_article_add @budget_id = @budget_id

-- append budgets_totals with article_id
	insert into budgets_totals(budget_id, goal_account_id, article_id, name)
	select distinct @budget_id, f.goal_account_id, f.article_id, a.name
	from #fact f
		join bdr_articles a on a.article_id = f.article_id
	where not exists(
		select 1 from budgets_totals 
		where budget_id = @budget_id 
			and goal_account_id = f.goal_account_id
			and article_id = f.article_id
		)
	
	update x set name = a.name
	from budgets_totals x
		join bdr_articles a on a.article_id = x.article_id
	where budget_id = @budget_id 	
		and isnull(x.name,'') <> a.name

-- update
	update budgets_totals set fact_dds = 0, fact_dds_self = 0 where budget_id = @budget_id

	update p
	set fact_dds = f.fact_dds
	from budgets_totals p
		join (
			select goal_account_id, article_id, sum(fact_dds) as fact_dds
			from #fact group by goal_account_id, article_id
		) f on f.goal_account_id = p.goal_account_id and f.article_id = p.article_id
	where p.budget_id = @budget_id
end
go
-- BUDGETS_TOTALS: FACT_DDS_GOAL
create proc budget_calc;40
	@budget_id int
as
begin

	if (select type_id from budgets where budget_id = @budget_id) = 4
	begin
		exec budget_calc;41 @budget_id
		return
	end

-- #plan
	create table #plan(row_id int identity primary key, id int, value decimal(18,2))

	insert into #plan(id, value)
	select b.id, abs(b.plan_rur)
	from budgets_plans b
		join bdr_articles a on a.article_id = b.article_id
		join budgets_periods per on per.budget_id = b.budget_id and per.budget_period_id = b.budget_period_id
		join budgets_totals t on t.budget_id = b.budget_id and t.article_id = b.article_id
	where b.budget_id = @budget_id
		and b.plan_rur < 0
		and a.has_childs = 0
		and per.is_selected = 1
	order by per.date_start, t.node_priority, a.sort_id

-- #fact
	create table #fact(row_id int identity primary key, article_id int, value decimal(18,2))

	insert into #fact(article_id, value)
	select a.article_id, sum(fact_dds)
	from budgets_totals b
		join bdr_articles a on a.article_id = b.article_id
	where budget_id = @budget_id
		and a.has_childs = 0
		and a.is_source = 1
		and b.fact_dds > 0
	group by a.article_id

-- fifo
	declare @left fifo_request
	declare @right fifo_request

	-- @left, @right
	insert into @left(row_id, group_id, value) select row_id, 0, value from #plan
	insert into @right(row_id, group_id, value) select row_id, 0, value from #fact

	-- calc
	declare @result fifo_response
	insert into @result exec fifo_calc @left, @right

-- update target	
	update budgets_plans set fact_rur_goal = null
	where budget_id = @budget_id

	update b
	set fact_rur_goal = -r.value
	from budgets_plans b
		join (
			select p.id, sum(r.value) as value
			from @result r
				join #plan p on p.row_id = r.left_row_id
			group by p.id
		) r on r.id = b.id
	where b.budget_id = @budget_id

	-- budgets_totals: clear
	update budgets_totals set fact_dds_goal = null
	where budget_id = @budget_id

	-- budgets_totals: факты
	update x
	set fact_dds_goal = y.fact_rur_goal
	from budgets_totals x
		join (
			select article_id, sum(fact_rur_goal) as fact_rur_goal
			from budgets_plans p
			where budget_id = @budget_id
			group by article_id
		) y on y.article_id = x.article_id
	where x.budget_id = @budget_id

	-- budgets_totals: источники финансирования
	update plans
	set fact_dds_goal = f.value
	from budgets_totals plans
		join #fact f on f.article_id = plans.article_id
	where plans.budget_id = @budget_id

end
go
-- BUDGETS_PLANFACT: операционные планы (TYPE_ID = 4)
create proc budget_calc;41
	@budget_id int
as
begin
	
	declare @subject_id int, @period_id varchar(16)
		select @subject_id = subject_id, @period_id = period_id
		from budgets where budget_id = @budget_id

	declare @result table(
		goal_account_id int,
		article_id int,
		account_id int,
		d_doc date,
		period_id varchar(16),		
		week_id varchar(30),
		value_plan float,
		value_fact float
		)

	insert into @result(goal_account_id, article_id, period_id, week_id, value_plan)
	select goal_account_id, article_id, @period_id, per.name, x.plan_rur
	from budgets_plans x
		join budgets_periods per on per.budget_id = x.budget_id and per.budget_period_id = x.budget_period_id
	where x.budget_id = @budget_id
		and x.has_childs = 0
		and x.plan_rur <> 0

	insert into @result(goal_account_id, article_id, account_id, d_doc, period_id, week_id, value_fact)
	select x.goal_account_id, x.article_id, x.account_id, x.d_doc, @period_id, per.name, sum(x.value_rur)
	from findocs# x
		join budgets_periods per on per.budget_id = @budget_id and x.d_doc between per.date_start and per.date_end
	where x.subject_id = @subject_id
	group by x.goal_account_id, x.article_id, x.account_id, x.d_doc, per.name

	delete from budgets_planfact where budget_id = @budget_id

	insert into budgets_planfact(budget_id, goal_account_id, article_id, account_id, d_doc, period_id, week_id, value_plan, value_fact)
	select @budget_id, goal_account_id, article_id, account_id, d_doc, @period_id, week_id, sum(value_plan), sum(value_fact)
	from @result
	group by goal_account_id, article_id, account_id, d_doc, week_id

end
go
-- BUDGETS_TOTALS: totals
create proc budget_calc;50
	@budget_id int
as
begin

-- budgets_plans totals
	exec budget_calc_node @budget_id = @budget_id -- plans
	
-- budgets_totals totals
	update budgets_totals
	set plan_bdr = 0, plan_dds = 0, plan_dds_current = 0, plan_dds_detailed = 0, fact_dds = 0
	where budget_id = @budget_id and has_childs = 1

	update x
	set plan_bdr = r.plan_bdr,
		plan_dds = r.plan_dds,
		plan_dds_current = r.plan_dds_current,
		plan_dds_detailed = r.plan_dds_detailed,
		fact_dds = r.fact_dds,
		fact_dds_self = r.fact_dds_self,		
		fact_dds_goal = r.fact_dds_goal
	from budgets_totals x
		join (
			select y2.id, 
				sum(y1.plan_bdr) as plan_bdr,
				sum(y1.plan_dds) as plan_dds,
				sum(y1.plan_dds_current) as plan_dds_current,
				sum(y1.plan_dds_detailed) as plan_dds_detailed,
				sum(y1.fact_dds) as fact_dds,
				sum(y1.fact_dds_self) as fact_dds_self,
				sum(y1.fact_dds_goal) as fact_dds_goal
			from budgets_totals y1
				cross apply budgets_totals y2
			where y1.budget_id = y2.budget_id
				and y1.goal_account_id = y2.goal_account_id
				and y1.node.IsDescendantOf(y2.node) = 1
				and y1.has_childs = 0
			group by y2.id
		) r on r.id = x.id
	where x.budget_id = @budget_id

end
go
