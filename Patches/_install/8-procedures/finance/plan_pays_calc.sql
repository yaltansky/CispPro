if object_id('plan_pays_calc') is not null drop procedure plan_pays_calc
go
-- exec plan_pays_calc 1000, '202203'
create proc plan_pays_calc
	@mol_id int = null,
	@period_id varchar(16) = null,
	@trace bit = 0
as
begin
	
	set nocount on;

	set @mol_id = isnull(@mol_id, -25) -- admin
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin,Finance.Plans.Admin,Finance.Plans.Reader')
	
-- reglament
	declare @managers as app_pkids
	if @is_admin = 0
	begin
		insert into @managers
		select mol_id from mols where mol_id = @mol_id or chief_id = @mol_id
	end

-- prepare
	if @period_id is null
		set @period_id = (select period_id from periods where type_id = 'month' and dbo.today() between date_start and date_end)

	declare @d_from datetime, @d_to datetime, @today datetime = dbo.today()
	select @d_from = date_start, @d_to = date_end from periods where period_id = @period_id

	declare @plans table(plan_pay_id int primary key)
	insert into @plans select plan_pay_id from plan_pays where period_id = @period_id and status_id = 10

	select top 0 * into #az from plan_pays_az
	
	declare @tid int; exec tracer_init 'deals_replicate', @trace_id = @tid out, @echo = @trace

	exec tracer_log @tid, 'plans'
		insert into #az(period_id, vendor_id, direction_id, mol_id, agent_id, agent_name, d_doc, pay_type_id, value_plan, note)
		select p.period_id, x.vendor_id, p.direction_id, p.mol_id, x.agent_id, x.agent_name, x.d_doc, x.pay_type_id, x.value_plan, x.note
		from plan_pays_rows x
			join plan_pays p on p.plan_pay_id = x.plan_pay_id
			join @plans px on px.plan_pay_id = p.plan_pay_id
		where (
			@is_admin = 1
			or p.mol_id in (select id from @managers)
			)

	exec tracer_log @tid, 'facts'
		insert into #az(period_id, subject_id, vendor_id, direction_id, mol_id, agent_id, deal_id, d_doc, value_fact)
		select @period_id, subject_id, vendor_id, direction_id, mol_id, agent_id, deal_id, d_doc, value_rur
		from (
			select
				f.subject_id,
				isnull(d.vendor_id, pc.vendor_id) as vendor_id,
				isnull(d.direction_id, chiefs.dept_id) as direction_id,
				isnull(d.manager_id, chiefs.mol_id) as mol_id,
				f.agent_id, d.deal_id, f.d_doc, f.value_rur
			from findocs# f
				join budgets b on b.budget_id = f.budget_id
					left join deals d on d.deal_id = b.project_id
					left join projects p on p.project_id = b.project_id
						left join mols chiefs on chiefs.mol_id = p.chief_id
						left join projects_contracts pc on pc.project_id = p.project_id
			where f.article_id = 24
				and f.d_doc between @d_from and @d_to
			) x
		where 
			(
				@is_admin = 1
				or x.mol_id in (select id from @managers)
				)

	exec tracer_log @tid, 'save results'
		delete from plan_pays_az where period_id = @period_id
			and (
				@is_admin = 1
				or mol_id in (select id from @managers)
				)
		
		insert into plan_pays_az(period_id, subject_id, vendor_id, direction_id, mol_id, agent_id, agent_name, pay_type_id, deal_id, d_doc, note, value_plan, value_fact)
		select period_id, subject_id, vendor_id, direction_id, mol_id, agent_id, agent_name, pay_type_id, deal_id, d_doc, note, sum(value_plan), sum(value_fact)
		from #az
		group by period_id, subject_id, vendor_id, direction_id, mol_id, agent_id, agent_name, pay_type_id, deal_id, d_doc, note

-- close log
	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid

-- drops
	drop table #az
end
go
