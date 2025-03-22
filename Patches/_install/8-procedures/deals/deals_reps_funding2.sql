if object_id('deals_reps_funding2') is not null drop proc deals_reps_funding2
go
-- exec deals_reps_funding2 1000, 9, @is_calc = 1
-- exec deals_reps_funding2 1000, 9
-- exec deals_reps_funding2 1000, 9, 16665
create proc deals_reps_funding2
	@mol_id int = -25,
	@principal_id int = 9,
	@folder_id int = null,	
	@is_calc bit = 0,
	@trace bit = 0
as
begin
	set nocount on;

	-- prepare
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @mol_id=', @mol_id,
			' @folder_id=', @folder_id,
			' @principal_id=', @principal_id
			)
		exec tracer_log @tid, @tid_msg

		declare @external_call bit = case when object_id('tempdb.dbo.#resultDealsRepsFunding2') is not null then 1 else 0 end

		if @external_call = 0
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

	-- recalc

		if @is_calc = 1 or not exists(select 1 from deals_r_funding)
		begin
			exec deals_reps_funding2;2 
				@mol_id = @mol_id,
				@principal_id = @principal_id,
				--/*debug*/ @folder_id = @folder_id,
				@is_calc = 1,
				@tid = @tid
					
			if @is_calc = 1 goto final
			else truncate table #resultdealsrepsfunding2
		end

		exec deals_reps_funding2;2 
			@mol_id = @mol_id,
			@principal_id = @principal_id,
			@folder_id = @folder_id,
			@tid = @tid

	-- final select
		if @external_call = 0
			select
				x.*,
				d.deal_hid,
				deal_number = d.number,
				d.dogovor_number,
				d.dogovor_date,
				d.spec_number,
				d.spec_date,
				d.crm_number,				
				d.pay_conditions,
				d.agent_name,
				d.vendor_name,
				d.direction_name,
				d.mol_name,
				article_group_name = isnull(ba2.name, '-'),
				article_name = ba.name,
				per_mfr_name = dbo.date2month(x.d_mfr),
				per_issue_name = dbo.date2month(x.d_issue),
				per_ship_name = dbo.date2month(x.d_ship),
				fund_payorder_hid = concat('#', x.fund_payorder_id)
			from #resultDealsRepsFunding2 x
				join v_deals d on d.deal_id = x.deal_id
				left join bdr_articles ba on ba.article_id = x.article_id
					left join bdr_articles ba2 on ba2.article_id = ba.parent_id

	final:
        exec tracer_close @tid
        if @trace = 1 exec tracer_view @tid

        if @external_call = 0 exec dbo.drop_temp_table '#resultDealsRepsFunding2'
end
GO
-- helper: recalc procedure
create proc deals_reps_funding2;2
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
        
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

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

	-- @is_calc, @is_save
        declare @is_save bit = @is_calc

        if @folder_id is not null
            -- не все сделки содержатся в регистре
            and exists(select 1 from @ids i where not exists(select 1 from deals_r_funding where deal_id = i.id))
        begin
            set @is_calc = 1
        end

        if @is_calc = 0 goto after_calc

	exec tracer_log @tid, 'ЧАСТЬ 1: Финансирование сделок (@resultFunds)'
		create table #resultFunds(
			row_id int identity primary key,
			--
			budget_id int index ix_budget,
			article_id int index ix_article,
			--
			p1_payorder_id int,
			p1_date datetime,
			p1_number varchar(500),
			p1_value float,
			--
			p2_payorder_id int,
			p2_date datetime,
			p2_number varchar(500),
			p2_value float,
			--
			value float,
			slice varchar(100),
			note varchar(max)
			)

		exec deals_reps_funding;2 
			@mol_id = @mol_id,
			@folder_id = @folder_id,
			@ids = @ids,
			@skip_access = 1

		declare @resultFunds table(
			deal_id int, article_id int, fund_payorder_id int, d_fund datetime, value_fund float,
			index ix_funds (deal_id, article_id, fund_payorder_id)
			)

		insert @resultFunds(deal_id, article_id, fund_payorder_id, d_fund, value_fund)
		select d.deal_id, x.article_id, x.p1_payorder_id, min(x.p1_date), isnull(sum(p2_value), 0) - isnull(sum(p1_value), 0)
		from #resultFunds x
			join deals d on d.budget_id = x.budget_id
		group by d.deal_id, x.article_id, x.p1_payorder_id

	exec tracer_log @tid, 'ЧАСТЬ 2: План/факт по сделкам (@resultPlanFact)'
		create table #resultBgPlanFact(
			budget_id int,
			article_id int,
			step_name varchar(100),
			agent_id int, d_doc datetime,
			value_plan decimal(18,2),
			value_fact decimal(18,2),
			--
			index ix_bgplanfact(budget_id, article_id)
			)

		exec finance_reps_bgplanfact;2
			@mol_id = @mol_id,
			@ids = @ids,
			@bydeals = 1,
			@principal_id = @principal_id,
			@skip_access = 1

		declare @resultPlanFact table(		
			deal_id int,
			article_id int,
			step_name varchar(100),
			d_fact_pay datetime,
			value_plan decimal(18,2), 
			value_fact decimal(18,2),
			index ix_plan_fact (deal_id, article_id)
			)

		insert into @resultPlanFact(deal_id, article_id, step_name, d_fact_pay, value_plan, value_fact)
		select d.deal_id, x.article_id, step_name, x.d_doc, sum(x.value_plan), sum(x.value_fact)
		from #resultBgPlanFact x
			join deals d on d.budget_id = x.budget_id
		group by d.deal_id, x.article_id, x.step_name, x.d_doc
    
    -- /*debug*/ select * from @resultPlanFact where deal_id = 22684 and article_id = 24

	exec tracer_log @tid, 'ЧАСТЬ 3: Статус обеспечения сделки (@resultProvides)'
		declare @resultProvides table(
			deal_id int index ix_deal,
			status_name varchar(50),
			mfr_number varchar(50),
			d_mfr datetime,
			d_issue datetime,
			d_issue_plan datetime,
			d_order datetime,
			d_ship datetime,
			d_delivery datetime,	
			q_mfr decimal(18,2),
			q_issue decimal(18,2),		
			q_order decimal(18,2),
			q_ship decimal(18,2),
			part float
			)

		insert into @resultProvides(
			deal_id, status_name, mfr_number,
			d_mfr, d_issue, d_issue_plan, d_order, d_ship, d_delivery,
			q_mfr, q_issue, q_order, q_ship,
			part
			)
		select 
			x.id_deal,
			x.status_name,
			x.mfr_number,
			max(x.d_mfr),
			max(x.d_issue),
			max(x.d_issue_plan),
			max(x.d_order),
			max(x.d_ship),
			max(x.d_delivery),
			sum(x.q_mfr),
			sum(x.q_issue),
			sum(x.q_order),
			sum(x.q_ship),
			sum(x.v_order) / nullif(xsum.v_order,0)
		from v_sdocs_provides x
			join (
				select id_deal, sum(v_order) as v_order from v_sdocs_provides group by id_deal
			) xsum on xsum.id_deal = x.id_deal
			join @ids i on i.id = x.id_deal
		group by x.id_deal, x.status_name, x.mfr_number, xsum.v_order

	exec tracer_log @tid, 'ЧАСТЬ 4: Прогноз поступлений'
		create table #resultDealsPaysFifo(
			row_id int identity primary key,
			--
			deal_id int index ix_deal,
			--
			b_date datetime,
			b_step varchar(100),
			b_article_id int,
			b_value decimal(18,2),
			--
			p_date datetime,
			p_step varchar(100),
			p_article_id int,
			p_value decimal(18,2),
			--
			f_date datetime,        
			f_number varchar(100),
			f_value decimal(18,2),
			--
			value decimal(18,2),		
			slice varchar(100),
			note varchar(max),
			--
			findoc_id int index ix_findoc
			)

		exec deals_reps_paysfifo;2
			@mol_id = @mol_id,
			@principal_id = @principal_id,
			@ids = @ids,
			@skip_access = 1

		declare @resultDealsPaysFifo table(
			deal_id int index ix_deal,
			step_name varchar(50),
			step_date datetime,
			article_id int,
			value_step decimal(18,2)
			)

		insert into @resultDealsPaysFifo(deal_id, step_name, step_date, article_id, value_step)
		select deal_id, p_step, p_date, p_article_id, sum(p_value)
		from #resultDealsPaysFifo
		where isnull(f_value,0) = 0
		group by deal_id, p_step, p_date, p_article_id

		insert into @resultDealsPaysFifo(deal_id, step_name, step_date, article_id, value_step)
		select deal_id, p_step, p_date, b_article_id, -sum(p_value)
		from #resultDealsPaysFifo
		where isnull(f_value,0) = 0
		group by deal_id, p_step, p_date, b_article_id

	exec tracer_log @tid, 'results'
		-- исполнение заказа
		insert into #resultDealsRepsFunding2(
			deal_id, status_name, mfr_number, d_mfr, d_issue, d_issue_plan, d_ship, d_order, d_delivery
			)
		select 
			x.deal_id,
			x3.status_name,
			x3.mfr_number,
			x3.d_mfr,
			x3.d_issue,
			x3.d_issue_plan,
			x3.d_ship,
			x3.d_order,
			x3.d_delivery
		from deals x
			join @ids i on i.id = x.deal_id
			join @resultProvides x3 on x3.deal_id = x.deal_id

		-- план/факт
		insert into #resultDealsRepsFunding2(
			deal_id, status_name, mfr_number, d_mfr, d_issue, d_issue_plan, d_ship, article_id, plan_pay_name, d_fact_pay, value_plan, value_fact
			)
		select 
			x.deal_id,
			x3.status_name,
			x3.mfr_number,
			x3.d_mfr,
			x3.d_issue,
			x3.d_issue_plan,
			x3.d_ship,
			x1.article_id,
			x1.step_name,
			x1.d_fact_pay,
			x1.value_plan * isnull(x3.part,1),
			x1.value_fact * isnull(x3.part,1)
		from deals x
			join @ids i on i.id = x.deal_id
			left join @resultPlanFact x1 on x1.deal_id = x.deal_id
			left join @resultProvides x3 on x3.deal_id = x.deal_id

		/*debug*/
		-- select 'deals_reps_funding2', sum(value_fact) from #resultDealsRepsFunding2 where deal_id = 4979 and article_id = 24

		-- финансирование
			insert into #resultDealsRepsFunding2(
				deal_id, status_name, mfr_number, d_mfr, d_issue, d_issue_plan, d_ship, article_id, fund_payorder_id, d_fund, value_fund
				)
			select 
				x.deal_id,
				x3.status_name,		
				x3.mfr_number,
				x3.d_mfr,
				x3.d_issue,
				x3.d_issue_plan,
				x3.d_ship,		
				x1.article_id,
				x1.fund_payorder_id,
				x1.d_fund,
				x1.value_fund * isnull(x3.part,1)
			from deals x
				join @ids i on i.id = x.deal_id
				left join @resultFunds x1 on x1.deal_id = x.deal_id
				left join @resultProvides x3 on x3.deal_id = x.deal_id

		-- прогноз поступлений
			insert into #resultDealsRepsFunding2(
				deal_id, status_name, mfr_number, d_mfr, d_issue, d_issue_plan, d_ship, plan_pay_name, d_plan_pay, article_id, value_plan_pay
				)
			select 
				x.deal_id,
				x3.status_name,
				x3.mfr_number,
				x3.d_mfr,
				x3.d_issue,
				x3.d_issue_plan,
				x3.d_ship,
				x1.step_name,
				x1.step_date,
				x1.article_id,
				x1.value_step * isnull(x3.part,1)
			from deals x
				join @ids i on i.id = x.deal_id
				left join @resultDealsPaysFifo x1 on x1.deal_id = x.deal_id
				left join @resultProvides x3 on x3.deal_id = x.deal_id

			update #resultDealsRepsFunding2 set plan_pay_name = '' where plan_pay_name is null

	after_calc:

	if @is_save = 1
	begin
		truncate table deals_r_funding

		insert into deals_r_funding(
			deal_id, status_name, mfr_number, article_id, fund_payorder_id, plan_pay_name, d_mfr, d_issue, d_issue_plan, d_ship, d_order, d_delivery, d_plan_pay, d_fact_pay, d_fund, value_plan, value_fact, value_fund, value_plan_pay
			)
		select 
			deal_id, status_name, mfr_number, article_id, fund_payorder_id, plan_pay_name, d_mfr, d_issue, d_issue_plan, d_ship, d_order, d_delivery, d_plan_pay, d_fact_pay, d_fund, value_plan, value_fact, value_fund, value_plan_pay
		from #resultdealsrepsfunding2
	end

	if @is_calc = 0
		insert into #resultdealsrepsfunding2(
			deal_id, status_name, mfr_number, article_id, fund_payorder_id, plan_pay_name, d_mfr, d_issue, d_issue_plan, d_ship, d_order, d_delivery, d_plan_pay, d_fact_pay, d_fund, value_plan, value_fact, value_fund, value_plan_pay
			)
		select 
			deal_id, status_name, mfr_number, article_id, fund_payorder_id, plan_pay_name, d_mfr, d_issue, d_issue_plan, d_ship, d_order, d_delivery, d_plan_pay, d_fact_pay, d_fund, value_plan, value_fact, value_fund, value_plan_pay
		from deals_r_funding x
			join @ids i on i.id = x.deal_id

	exec dbo.drop_temp_table '#resultFunds,#resultBgPlanFact,#resultDealsPaysFifo'
end
GO
