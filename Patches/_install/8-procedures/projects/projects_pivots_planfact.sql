if object_id('projects_pivots_planfact') is not null drop proc projects_pivots_planfact
go
-- exec projects_pivots_planfact 1000, 12763
create proc projects_pivots_planfact
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	-- @budgets
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit = 
		case 
			when exists(select 1 from @budgets where id = -1) and not exists(select 1 from @budgets where id <> -1) then 1 
			else 0 
		end

-- @ids
	declare @keyword varchar(50) = (select keyword from objs_folders where folder_id = @folder_id)
	declare @ids as app_pkids

	if @keyword = 'BUFFER' set @keyword = 'PROJECT'
	
	if @keyword = 'PROJECT'
		insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'prj'
	else if @keyword = 'BUDGET'
		insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'bdg'

-- #buf_budgets
	create table #buf_budgets(budget_id int primary key, project_id int)

	if @keyword = 'PROJECT'
	begin
		-- сначала проекты программ
		insert into #buf_budgets(budget_id, project_id)
		select b.budget_id, max(p.project_id)
		from projects p
			join @ids i on i.id = p.project_id
			join projects_tasks pt on pt.project_id = p.project_id
				join budgets b on b.project_id = pt.ref_project_id
		where b.is_deleted = 0
			and (@all_budgets = 1 or b.budget_id in (select id from @budgets))
		group by b.budget_id

		-- ... затем остальные проекты
		insert into #buf_budgets(budget_id, project_id)
		select b.budget_id, p.project_id
		from projects p
			join @ids i on i.id = p.project_id
			join budgets b on b.project_id = p.project_id 
		where b.is_deleted = 0
			and not exists(select 1 from #buf_budgets where budget_id = b.budget_id)
			and (@all_budgets = 1 or b.budget_id in (select id from @budgets))
	end

	else
		insert into #buf_budgets(budget_id, project_id)
		select distinct b.budget_id, b.project_id
		from budgets b
			join @ids i on i.id = b.budget_id
		where b.is_deleted = 0
			and (@all_budgets = 1 or b.budget_id in (select id from @budgets))
	
-- #result
	create table #result(
		subject_id int,
		budget_id int index ix_budgets,
		deal_id int,
		article_id int,
		agent_id int,
		findoc_id int,
		pay_account_name varchar(50),
		pay_date datetime,
		pay_number varchar(50),
		pay_note varchar(max),
		value_plan decimal(18,2),
		value_fact decimal(18,2)
		)

	-- планы проектов
	insert into #result(subject_id, budget_id, article_id, value_plan)
	select pc.subject_id, pl.budget_id, pl.article_id, sum(pl.plan_dds) as value_plan
	from budgets_totals pl
		join #buf_budgets bufb on bufb.budget_id = pl.budget_id
		join budgets b on b.budget_id = pl.budget_id
			left join projects p on p.project_id = b.project_id
				left join projects_contracts pc on pc.project_id = p.project_id
	where pl.has_childs = 0
		and isnull(pl.plan_dds,0) <> 0
		and p.type_id <> 3
	group by pc.subject_id, pl.budget_id, pl.article_id

	-- планы проекных сделок
	insert into #result(subject_id, budget_id, deal_id, article_id, agent_id, value_plan)
	select d.subject_id, d.budget_id, d.deal_id, db.article_id, d.customer_id, sum(value_bds) as value_plan
	from deals_budgets db
		join deals d on d.deal_id = db.deal_id
			join #buf_budgets bufb on bufb.budget_id = d.budget_id						
	group by d.subject_id, d.budget_id, d.deal_id, db.article_id, d.customer_id

	-- факты по всем бюджетам (проекты, проектные сделки)
	insert into #result(subject_id, budget_id, article_id, agent_id, findoc_id, pay_account_name, pay_date, pay_number, pay_note, value_fact)
	select 
		f.subject_id, f.budget_id, f.article_id, f.agent_id,
		f.findoc_id, fa.name, f.d_doc, ff.number, ff.note,
		f.value_rur
	from findocs# f
		join #buf_budgets bufb on bufb.budget_id = f.budget_id				
		join findocs ff on ff.findoc_id = f.findoc_id
		left join findocs_accounts fa on fa.account_id = f.account_id
		left join agents ag on ag.agent_id = f.agent_id

	;with bdg as (
		select budget_id, max(subject_id) as subject_id
		from #result where subject_id is not null
		group by budget_id
		)
		update x set subject_id = bdg.subject_id
		from #result x
			join bdg on bdg.budget_id = x.budget_id
		where x.subject_id is null

-- final
	select
		subject_name = subj.short_name,
		direction_name = depts.name,
		mol_name = mols.name,
		program_name = isnull(prog.name, '-'),
		project_name = p.name,
		budget_name = b.name,
		status_name = ps.name,
		article_group_name1 = a1.name,
		article_group_name2 = a2.name,
		article_name = a3.name,
		agent_name = ag.name,
		x.pay_account_name,
		x.pay_date,
		x.pay_number,
		x.pay_note,
		--
		x.value_plan,
		x.value_fact,
		--
		p.project_id,
		x.deal_id,
		x.budget_id,
		x.article_id,
		x.findoc_id
	from #result x
		join budgets b on b.budget_id = x.budget_id
		join #buf_budgets xb on xb.budget_id = x.budget_id
			join projects p on p.project_id = xb.project_id
				join projects_statuses ps on ps.status_id = p.status_id
				join mols on mols.mol_id = p.chief_id
					join depts on depts.dept_id = mols.dept_id
				left join projects prog on prog.project_id = p.parent_id and prog.type_id = 2
		left join subjects subj on subj.subject_id = x.subject_id
		left join bdr_articles a3 on a3.article_id = x.article_id
			left join bdr_articles a2 on a2.article_id = a3.parent_id
				left join bdr_articles a1 on a1.article_id = a2.parent_id
		left join agents ag on ag.agent_id = x.agent_id

	drop table #buf_budgets, #result
end
go
