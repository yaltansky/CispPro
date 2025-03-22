if object_id('deals_reps_work_capital') is not null drop proc deals_reps_work_capital
go
-- exec deals_reps_work_capital 1000, 9, @is_calc = 1
-- exec deals_reps_work_capital 1000, 9
-- exec deals_reps_work_capital 1000, 9, 16665
create proc deals_reps_work_capital
	@mol_id int = -25,
	@principal_id int = 9,
	@folder_id int = null,
	@is_calc bit = 0,
	@trace bit = 0
as
begin

	set nocount on;

begin

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
		' @mol_id=', @mol_id,
		' @folder_id=', @folder_id,
		' @principal_id=', @principal_id
		)
	exec tracer_log @tid, @tid_msg

	create table #resultDealsWorkCapital(
		deal_id int index ix_deal,
		deal_number varchar(50),
		agent_name varchar(150),
		pay_conditions varchar(50),
		mfr_number varchar(50),
		vendor_name varchar(150),
		direction_name varchar(100),
		mol_name varchar(50),
		article_group_name varchar(150),
		plan_pay_name varchar(50),
		d_plan_pay datetime,
		d_fact_pay datetime,
		group1_name varchar(50),
		group2_name varchar(50),
		status_name varchar(30),
		value_plan decimal(18,2),
		value_fact decimal(18,2),
		value_fund decimal(18,2),
		value_plan_pay decimal(18,2),
		--
		article_group_id int,
		)

end -- prepare

begin

	if @is_calc = 1 or not exists(select 1 from deals_r_work_capital)
	begin
		exec deals_reps_work_capital;2 
			@mol_id = @mol_id,
			@principal_id = @principal_id,
			--/*debug*/@folder_id = @folder_id,
			@is_calc = 1,
			@tid = @tid
					
		if @is_calc = 1 goto final
		else truncate table #resultDealsWorkCapital
	end

	exec deals_reps_work_capital;2 
		@mol_id = @mol_id,
		@principal_id = @principal_id,
		@folder_id = @folder_id,
		@tid = @tid

end -- recalc

-- final select
	select x.*,
		agent_inn = a.inn
	from #resultdealsworkcapital x	
		join deals d on d.deal_id = x.deal_id
			join agents a on a.agent_id = d.deal_id

final:
	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid

	exec dbo.drop_temp_table '#resultDealsWorkCapital'
end
GO
-- helper: recalc procedure
create proc deals_reps_work_capital;2
	@mol_id int,
	@principal_id int,
	@folder_id int = null,
	@is_calc bit = 0,
	@tid int = 0
as
begin

	-- access meta
		declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
		declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
		declare @vendors as app_pkids; insert into @vendors select distinct obj_id from @objects where obj_type = 'vnd'
		declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
		declare @all_budgets bit = case when exists(select 1 from @budgets where id = -1) then 1 else 0 end

	-- @ids	
		declare @idsTmp as app_pkids;
		if @folder_id is not null
			insert into @idsTmp exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'
		else
			insert into @idsTmp 
			select d.deal_id from deals d
				join deals_statuses s on s.status_id = d.status_id and s.is_current = 1

		declare @ids as app_pkids
		insert into @ids select deal_id from deals d
			join @idsTmp i on i.id = d.deal_id
		where
			-- access
			(
			d.subject_id in (select id from @subjects)
			or d.vendor_id in (select id from @vendors)
			or (@all_budgets = 1 or d.budget_id in (select id from @budgets))
			)

	if @is_calc = 0 goto after_calc

		create table #resultDealsRepsFunding2(
			deal_id int index ix_deal,
			status_name varchar(50),
			mfr_number varchar(50),
			article_id int,
			fund_payorder_id int,
			plan_pay_name varchar(50),
			d_mfr datetime,
			d_issue datetime,
			d_issue_plan datetime,
			d_ship datetime,
			d_order datetime,
			d_delivery datetime,	
			d_plan_pay datetime,	
			d_fact_pay datetime,
			d_fund datetime,
			value_plan decimal(18,2),
			value_fact decimal(18,2),
			value_fund decimal(18,2),
			value_plan_pay decimal(18,2)
			)

		exec deals_reps_funding2
			@mol_id = @mol_id,
			@principal_id = @principal_id
			--/*debug*/, @folder_id = @folder_id, @is_calc = 1

	-- debug
		--select 'deals_reps_work_capital', sum(value_fact) from #resultDealsRepsFunding2 where deal_id = 4979 and article_id = 24

		insert into #resultDealsWorkCapital(
			deal_id, deal_number, agent_name, pay_conditions, mfr_number, vendor_name, direction_name, mol_name, article_group_name, plan_pay_name, d_plan_pay, d_fact_pay,
			status_name, article_group_id,
			value_plan, value_fact, value_fund, value_plan_pay
			)
		select 
			x.deal_id, d.number, d.agent_name, d.pay_conditions, x.mfr_number, d.vendor_name, d.direction_name, d.mol_name, isnull(ba2.name, '-'), x.plan_pay_name, x.d_plan_pay, x.d_fact_pay,
			x.status_name, ba2.article_id,
			sum(value_plan), sum(value_fact), sum(value_fund), sum(value_plan_pay)		
		from #resultDealsRepsFunding2 x
			join v_deals d on d.deal_id = x.deal_id
			left join bdr_articles ba on ba.article_id = x.article_id
				left join bdr_articles ba2 on ba2.article_id = ba.parent_id
		group by 
			x.deal_id, d.number, d.agent_name, d.pay_conditions, x.mfr_number, d.vendor_name, d.direction_name, d.mol_name, isnull(ba2.name, '-'), x.plan_pay_name, x.d_plan_pay, x.d_fact_pay,
			x.status_name, ba2.article_id

		exec dbo.drop_temp_table '#resultDealsRepsFunding2'
			
		update #resultDealsWorkCapital set article_group_id = 0 where article_group_id is null
		
		declare @article_incomes int = (select top 1 article_id from bdr_articles where name like '%Поступления от операционной деятельности')

		-- Раздел “Оборотные активы”
			update #resultDealsWorkCapital set group1_name = 'Оборотные активы',
				group2_name = '1-Заказы в проработке'
			where status_name is null and article_group_id = @article_incomes

			update #resultDealsWorkCapital set group1_name = 'Оборотные активы',
				group2_name = '2-Заказы в производстве'
			where status_name = 'Производство' and article_group_id = @article_incomes

			update #resultDealsWorkCapital set group1_name = 'Оборотные активы',
				group2_name = '3-Готовая продукция'
			where status_name = 'Склад' and article_group_id = @article_incomes

			update #resultDealsWorkCapital set group1_name = 'Оборотные активы',
				group2_name = '4-Дебиторская задолженность'
			where status_name = 'Дебиторка' and article_group_id = @article_incomes
			
		-- Раздел “Расчёты с Поставщиками”
			update #resultDealsWorkCapital set group1_name = 'Расчёты с Поставщиками',
				group2_name = '1-Расчёты по заказам в проработке'
			where status_name is null and article_group_id <> @article_incomes

			update #resultDealsWorkCapital set group1_name = 'Расчёты с Поставщиками',
				group2_name = '2-Расчёты по заказам в производстве'
			where status_name = 'Производство' and article_group_id <> @article_incomes

			update #resultDealsWorkCapital set group1_name = 'Расчёты с Поставщиками',
				group2_name = '3-Расчёты по готовой продукции'
			where status_name = 'Склад' and article_group_id <> @article_incomes

			update #resultDealsWorkCapital set group1_name = 'Расчёты с Поставщиками',
				group2_name = '4-Расчёты по дебиторской задолженности'
			where status_name = 'Дебиторка' and article_group_id <> @article_incomes

		delete from #resultDealsWorkCapital where group1_name is null

	after_calc:

		if @is_calc = 1
		begin
			truncate table deals_r_work_capital

			insert into deals_r_work_capital(
				deal_id, deal_number, agent_name, pay_conditions, mfr_number, vendor_name, direction_name, mol_name, article_group_name, plan_pay_name, d_plan_pay, d_fact_pay,
				group1_name, group2_name, status_name,
				value_plan, value_fact, value_fund, value_plan_pay
				)
			select 
				deal_id, deal_number, agent_name, pay_conditions, mfr_number, vendor_name, direction_name, mol_name, article_group_name, plan_pay_name, d_plan_pay, d_fact_pay,
				group1_name, group2_name, status_name,
				value_plan, value_fact, value_fund, value_plan_pay
			from #resultDealsWorkCapital
		end

		else
			insert into #resultDealsWorkCapital(
				deal_id, deal_number, agent_name, pay_conditions, mfr_number, vendor_name, direction_name, mol_name, article_group_name, plan_pay_name, d_plan_pay, d_fact_pay,
				group1_name, group2_name, status_name,
				value_plan, value_fact, value_fund, value_plan_pay
				)
			select 
				deal_id, deal_number, agent_name, pay_conditions, mfr_number, vendor_name, direction_name, mol_name, article_group_name, plan_pay_name, d_plan_pay, d_fact_pay, 
				group1_name, group2_name, status_name,
				value_plan, value_fact, value_fund, value_plan_pay
			from deals_r_work_capital x
				join @ids i on i.id = x.deal_id

end
GO
