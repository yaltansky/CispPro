if object_id('mfr_plan_rates_calc') is not null drop proc mfr_plan_rates_calc
go
-- exec mfr_plan_rates_calc 1000
create proc mfr_plan_rates_calc
	@mol_id int = null,
	@version_id int = 0,
	@skip_planfact bit = 0,
	@trace bit = 0
as
begin
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- prepare
		delete from mfr_plans_rates where is_deleted = 1

		if @version_id = 0 and exists(select 1 from mfr_plans_vers)
			set @version_id = (select max(version_id) from mfr_plans_vers)
	-- declares
		declare @forecast_shift int = isnull(cast((select dbo.app_registry_value('MfrPlanForecastShift')) as int), 0)
		declare @today date = dbo.today()
		declare @fid uniqueidentifier set @fid = newid()

		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:')
		exec tracer_log @tid, @tid_msg
	-- dates
		declare @d_doc date = isnull((select d_doc from mfr_plans_vers where version_id = @version_id), dbo.today())
		declare @ext_type_id int = 
            case
                when isnull((select include_forecast from mfr_plans_vers where version_id = @version_id), 0) = 0 then 0
                else 1
            end
		declare @d_from date = @d_doc
		declare @d_hist_from date = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)
		declare @d_hist_to date = dateadd(d, -1, @d_doc)

	-- access
		declare @subject_id int = (select top 1 subject_id from mfr_sdocs where plan_status_id = 1 and status_id >= 0)
		if dbo.isinrole_byobjs(@mol_id, 'Mfr.Admin', 'SBJ', @subject_id) = 0
		begin
			raiserror('У Вас нет доступа к пересчёту базового плана в данном субъекте учёта.', 16, 1)
			return
		end
	-- tables
		create table #calendar(
			cal_row_id int identity primary key,
			product_group_id int index ix_product,
			d_doc date,
			value float
			)
			create unique index ix_calendar on #calendar(product_group_id, d_doc)
			
		create table #fixed(
			fx_row_id int identity primary key,
			product_group_id int index ix_product,
            priority_sort varchar(50),
			mfr_doc_id int,
			d_doc date,
			item_id int,
			quantity float
			)

		create table #orders(
			ord_row_id int identity primary key,
			product_group_id int index ix_product,
			priority_sort varchar(50),
			mfr_doc_id int,
			d_issue_fix date,
			d_issue_rule date,
			d_issue_forecast date,
			item_id int,
			value float
			)
		
        create table #facts(
			fact_row_id int identity primary key,
			product_group_id int index ix_product,
			mfr_doc_id int,
			d_doc date,
			item_id int,
			fact_q float
			)
			
		create table #result(		
			cal_row_id int index ix_cal_row,
			ord_row_id int index ix_ord_row,
			product_group_id int index ix_oper,
			d_doc datetime,
			plan_q float,
			mfr_doc_id int,
			item_id int,
			order_q float,
			slice varchar(20)
			)	
	-- get data
		declare @docs as app_pkids
		insert into @docs select doc_id from mfr_sdocs 
        where plan_status_id = 1 -- открытые папки планов
            and status_id >= 0 -- статусы от Черновика (включительно)
            and isnull(ext_type_id, @ext_type_id) = @ext_type_id -- заказы [+ прогнозы]
		
		exec tracer_log @tid, '#calendar', 1
			insert into #calendar(product_group_id, d_doc, value)
			select x.product_group_id, x.d_doc, x.limit_q
			from mfr_plans_rates x
				join mfr_attrs a on a.attr_id = x.product_group_id
			where x.d_doc >= @d_from
			order by product_group_id, d_doc

			if @trace = 1 select * into #trace_calendar from #calendar
		
        exec tracer_log @tid, '#fixed', 1
			insert into #fixed(product_group_id, d_doc, priority_sort, mfr_doc_id, item_id, quantity)
			select
				isnull(pg.plan_group_id, 0),
				ms.d_to_plan_hand,
				sd.priority_sort, sp.doc_id, sp.product_id, sp.quantity
			from sdocs_products sp
				join mfr_sdocs sd on sd.doc_id = sp.doc_id
				join @docs i on i.id = sd.doc_id
				join (
					select doc_id, product_id, d_to_plan_hand
					from mfr_sdocs_milestones ms
						join mfr_attrs a on a.attr_id = ms.attr_id
					where a.name like '%Готовая продукция%'
						and d_to_plan_hand is not null
				) ms on ms.doc_id = sp.doc_id and ms.product_id = sp.product_id
				left join products pg on pg.product_id = sp.product_id
			order by ms.d_to_plan_hand, sd.priority_sort, sd.d_ship
		
        exec tracer_log @tid, '#orders', 1
			-- Заказы
			insert into #orders(
                product_group_id, priority_sort, mfr_doc_id, 
                d_issue_fix, d_issue_forecast, d_issue_rule, 
                item_id, value
                )
			select 
                product_group_id, priority_sort, mfr_doc_id, 
                d_issue_fix, d_issue_forecast,
                d_issue_rule = isnull(d_issue_fix, d_issue_forecast), 
                product_id, value
            from (
                select
                    product_group_id,
                    priority_sort,
                    mfr_doc_id, 
                    d_ship10,
                    d_issue_fix,
                    d_issue_forecast = case when d_issue_forecast < d_ship10 then d_ship10 else d_issue_forecast end,
                    product_id, value
                from (
                    -- fixed
                    select
                        product_group_id,
                        priority_sort,
                        mfr_doc_id,
                        d_ship10 = d_doc,
                        d_issue_fix = d_doc,
                        d_issue_forecast = d_doc,
                        product_id = item_id,
                        value = quantity
                    from #fixed

                    -- normal
                    UNION ALL
                    select
                        product_group_id = isnull(pg.plan_group_id, 0),
                        sd.priority_sort,
                        mfr_doc_id = sd.doc_id,
                        d_ship10 = dateadd(d, -10, sd.d_ship),
                        d_issue_fix = null,
                        d_issue_forecast = coalesce(
                            case
                                when pg.plan_group_id is null then isnull(sd.d_ship, @d_from)
                                when sd.d_issue is not null then sd.d_issue
                                when dateadd(d, @forecast_shift, sd.d_issue_forecast) < @today then @d_from
                                else dateadd(d, @forecast_shift, sd.d_issue_forecast)
                            end,
                            sd.d_issue_plan
                            ),
                        r.product_id,
                        value = r.quantity
                    from sdocs_products r
                        join @docs i on i.id = r.doc_id
                        join (
                            select 
                                doc_id,
                                d_ship,
                                d_issue,
                                d_issue_forecast = isnull(d_issue_forecast, dateadd(d, -10, d_ship)),
                                d_issue_plan,
                                priority_sort
                            from mfr_sdocs
                        ) sd on sd.doc_id = r.doc_id
                        left join products pg on pg.product_id = r.product_id
                    where not exists(select 1 from #fixed where mfr_doc_id = r.doc_id)
                    ) x
                ) x 
			order by product_group_id, priority_sort, d_ship10, mfr_doc_id, product_id

        exec tracer_log @tid, '#facts', 1
			insert into #facts(product_group_id, d_doc, mfr_doc_id, item_id, fact_q)
			select product_group_id, closed_date, mfr_doc_id, product_id, closed_q
			from (
				select 
					product_group_id = isnull(pg.plan_group_id,0),
					r.mfr_doc_id,
					r.product_id,
					r.closed_date,
					r.closed_q
				from v_mfr_r_plans_jobs_products r
					left join products pg on pg.product_id = r.product_id
				where closed_date < @today
				) x
			order by product_group_id, closed_date, mfr_doc_id, product_id
            
			-- apply facts (на начало периода)
				update x set value = x.value - f.fact_q
				from #orders x
					join (
						select mfr_doc_id, item_id, fact_q = sum(fact_q)
						from #facts
						where d_doc < @d_from
						group by mfr_doc_id, item_id
					) f on f.mfr_doc_id = x.mfr_doc_id and f.item_id = x.item_id

				-- остаются только не исполненные на начало периода заказы
				delete from #orders where value <= 0

			if @trace = 1 select * into #trace_orders from #orders

	-- FIFO = #calendar + #orders
		exec tracer_log @tid, 'FIFO'
		
		insert into #result(
			cal_row_id, ord_row_id,
			product_group_id, d_doc, plan_q, 
			mfr_doc_id, item_id, order_q,
			slice
			)
		select 
			r.cal_row_id, p.ord_row_id,
			r.product_group_id, r.d_doc, f.value,
			p.mfr_doc_id, p.item_id, f.value,
			'mix'
		from #calendar r
			join #orders p on p.product_group_id = r.product_group_id and r.d_doc >= p.d_issue_rule
			cross apply dbo.fifo(@fid, p.ord_row_id, p.value, r.cal_row_id, r.value) f
		order by r.cal_row_id, p.ord_row_id

		-- left (calendar)
			insert into #result(cal_row_id, product_group_id, d_doc, plan_q, slice)
			select x.cal_row_id, x.product_group_id, x.d_doc, f.value, 'left'
			from dbo.fifo_left(@fid) f
				join #calendar x on x.cal_row_id = f.row_id
			where f.value > 0

			insert into #result(cal_row_id, product_group_id, d_doc, plan_q, slice)
			select x.cal_row_id, x.product_group_id, x.d_doc, x.value, 'left'
			from #calendar x
			where not exists(select 1 from #result where cal_row_id = x.cal_row_id)

		-- right (orders)
			insert into #result(ord_row_id, product_group_id, d_doc, mfr_doc_id, item_id, order_q, slice)
			select x.ord_row_id, x.product_group_id, x.d_issue_forecast, x.mfr_doc_id, x.item_id, f.value, 'right'
			from dbo.fifo_right(@fid) f
				join #orders x on x.ord_row_id = f.row_id
			where f.value > 0

			insert into #result(ord_row_id, product_group_id, d_doc, mfr_doc_id, item_id, order_q, slice)
			select x.ord_row_id, x.product_group_id, x.d_issue_forecast, x.mfr_doc_id, x.item_id, x.value, 'right'
			from #orders x
			where not exists(select 1 from #result where ord_row_id = x.ord_row_id)

		exec fifo_clear @fid

		-- normalize
		update #result set d_doc = @today, slice = concat(slice, '+nulldate') where d_doc is null

		-- checksum
		if @trace = 1			
			select 
				check_calendar = calendar - r_calendar,
				check_orders = orders - r_orders
			from (
			select 
				cast((select sum(value) from #trace_calendar) as int) as 'calendar',
				cast((select sum(plan_q) from #result) as int) as 'r_calendar',
				cast((select sum(value) from #trace_orders) as int) as 'orders',
				cast((select sum(order_q) from #result) as int) as 'r_orders'
				) u

	-- append facts (для заказов, которых нет в #result)
		;with hist as (
			select distinct mfr_doc_id, item_id
			from #facts f
			where not exists(select 1 from #result where mfr_doc_id = f.mfr_doc_id and item_id = f.item_id)
				and d_doc between @d_hist_from and @d_hist_to
			)
			insert into #result(product_group_id, d_doc, mfr_doc_id, item_id, plan_q, order_q, slice)
			select product_group_id, d_doc, f.mfr_doc_id, f.item_id, fact_q, fact_q, 'hist'
			from #facts f
				join hist h on h.mfr_doc_id = f.mfr_doc_id and h.item_id = f.item_id

	-- append early facts (для заказов, которые есть в #result)
		insert into #result(product_group_id, d_doc, mfr_doc_id, item_id, plan_q, order_q, slice)
		select product_group_id, d_doc, mfr_doc_id, item_id, fact_q, fact_q, 'facts'
		from #facts f
		where exists(select 1 from #orders where mfr_doc_id = f.mfr_doc_id and item_id = f.item_id)
			and d_doc < @d_from
	
	-- save results
		delete from mfr_r_plans_rates where version_id = @version_id

		insert into mfr_r_plans_rates(version_id, product_group_id, d_doc, mfr_doc_id, item_id, plan_q, order_q, slice)
		select @version_id, product_group_id, d_doc, mfr_doc_id, item_id, plan_q, order_q, slice
		from #result
		
		declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%Готовая продукция%')

		-- d_doc | d_order
		update r set d_order = d_doc, d_doc = null
		from mfr_r_plans_rates r
		where version_id = @version_id 
			and plan_q is null
			and product_group_id != 0
			-- нет фиксированных заказов
			and not exists(
				select 1 from sdocs_mfr_milestones
				where doc_id = r.mfr_doc_id
					and attr_id = @attr_product
					and d_to_plan_hand is not null
				)
		-- product_group_id = 0
		update mfr_r_plans_rates set plan_q = order_q, slice = 'group-0'
		where version_id = @version_id and product_group_id = 0

		-- checksum
		if @trace = 1
			select 'заказ <--> план:' = '-->', sp.doc_id, sp.product_id, sp.quantity, r.q
			from sdocs_products sp
				join (
					select mfr_doc_id, item_id, q = sum(order_q)
					from mfr_r_plans_rates
					where version_id = @version_id
					group by mfr_doc_id, item_id
				) r on r.mfr_doc_id = sp.doc_id and r.item_id = sp.product_id
			where sp.quantity != r.q

	-- back update
		
		-- normalize milestones
		insert into mfr_sdocs_milestones(doc_id, product_id, attr_id, ratio)
		select distinct sp.doc_id, sp.product_id, @attr_product, 1
		from sdocs_products sp
			join mfr_sdocs sd on sd.doc_id = sp.doc_id
		where not exists(
			select 1 from mfr_sdocs_milestones where doc_id = sp.doc_id and product_id = sp.product_id
				and attr_id = @attr_product
			)

		-- sdocs_mfr_milestones
		update x set d_to_plan_auto = r.d_plan
		from mfr_sdocs_milestones x
			join (
				select mfr_doc_id, d_plan = min(d_doc)
				from mfr_r_plans_rates
				where version_id = @version_id
					and isnull(d_doc,@d_from) >= @d_from
				group by mfr_doc_id
			) r on r.mfr_doc_id = x.doc_id
		where x.attr_id = @attr_product

		-- sdocs
		update x set d_issue_plan = r.d_plan
		from sdocs x
			join (
				select doc_id, d_plan = min(d_to_plan_auto)
				from mfr_sdocs_milestones ms
				where attr_id = @attr_product
				group by doc_id
			) r on r.doc_id = x.doc_id		
			join (
				select distinct mfr_doc_id from mfr_r_plans_rates
				where version_id = @version_id
			) rr on rr.mfr_doc_id = x.doc_id

		if @skip_planfact = 0
			exec mfr_plan_rates_calc;2 @version_id = @version_id, @enforce = 1 -- mfr_r_planfact

	final:
		exec drop_temp_table '#calendar,#trace_calendar,#orders,#temp_orders,#facts,#result'
		exec tracer_close @tid
		-- if @trace = 1 exec tracer_view @tid
end
go
-- helper: calc mfr_r_planfact
create proc mfr_plan_rates_calc;2
	@version_id int = 0,
	@enforce bit = 0,
	@trace bit = 0
as
begin

	SET NOCOUNT ON;	

	if @version_id = 0 and exists(select 1 from mfr_plans_vers)
		set @version_id = (select max(version_id) from mfr_plans_vers)

	declare @d_calc datetime = isnull((select top 1 d_calc from mfr_r_planfact where version_id = @version_id), '1900-01-01')
	if @enforce = 0 and datediff(minute, @d_calc, getdate()) < 5
	begin
		print 'Register MFR_R_PLANFACT is actual. No calculation nedeed.'
		return -- not expired
	end

	-- dates
		declare @d_doc date = (select d_doc from mfr_plans_vers where version_id = @version_id)
		declare @d_from date = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)

	-- tables
		create table #fifo(
			plan_row_id int index ix_plan,
			fact_row_id int index ix_fact,
			mfr_doc_id int,
			product_id int,
			d_plan date,
			d_fact date,
			plan_q float,
			fact_q float,
			index ix (mfr_doc_id, product_id)
			)

		declare @plan table(
			plan_row_id int identity primary key,
			mfr_doc_id int,
			product_id int,
			d_plan date,
			value float,
			index ix_join (mfr_doc_id, product_id)
		)
		declare @fact table(
			fact_row_id int identity primary key,
			mfr_doc_id int,
			product_id int,
			d_fact date,
			value float,
			index ix_join (mfr_doc_id, product_id)
		)
	-- fill
		insert into @plan(mfr_doc_id, product_id, d_plan, value)
		select
			sd.doc_id,
			r.item_id,
			r.d_doc,
			r.order_q
		from mfr_r_plans_rates r
			join mfr_sdocs sd on sd.doc_id = r.mfr_doc_id
		where r.version_id = @version_id
			and r.d_doc is not null
			and r.order_q > 0
		order by sd.doc_id, r.d_doc

		if @trace = 1 select * into #trace_plan from @plan

		insert into @fact(mfr_doc_id, product_id, d_fact, value)
		select mfr_doc_id, product_id, closed_date, closed_q
		from v_mfr_r_plans_jobs_products r
		where closed_q > 0
			and (
				exists(select 1 from @plan where mfr_doc_id = r.mfr_doc_id)
				or r.closed_date >= @d_from
			)
		order by mfr_doc_id, closed_date

		if @trace = 1 select * into #trace_fact from @fact

	-- select * from @fact where mfr_doc_id = 2084210
	-- return

	-- FIFO
		declare @fid uniqueidentifier set @fid = newid()

		insert into #fifo(
			plan_row_id, fact_row_id,
			mfr_doc_id, product_id, d_plan, d_fact, plan_q, fact_q
			)
		select 
			r.plan_row_id, p.fact_row_id,
			r.mfr_doc_id, r.product_id, r.d_plan, p.d_fact,
			f.value, f.value
		from @plan r
			join @fact p on p.mfr_doc_id = r.mfr_doc_id and r.product_id = p.product_id
			cross apply dbo.fifo(@fid, p.fact_row_id, p.value, r.plan_row_id, r.value) f
		order by r.plan_row_id, p.fact_row_id

	-- left (plans)
		insert into #fifo(plan_row_id, mfr_doc_id, product_id, d_plan, plan_q)
		select x.plan_row_id, x.mfr_doc_id, x.product_id, x.d_plan, f.value
		from dbo.fifo_left(@fid) f
			join @plan x on x.plan_row_id = f.row_id
		where f.value > 0

		insert into #fifo(plan_row_id, mfr_doc_id, product_id, d_plan, plan_q)
		select x.plan_row_id, x.mfr_doc_id, x.product_id, x.d_plan, x.value
		from @plan x
		where not exists(select 1 from #fifo where plan_row_id = x.plan_row_id)

	-- right (facts)
		insert into #fifo(fact_row_id, mfr_doc_id, product_id, d_fact, fact_q)
		select x.fact_row_id, x.mfr_doc_id, x.product_id, x.d_fact, f.value
		from dbo.fifo_right(@fid) f
			join @fact x on x.fact_row_id = f.row_id
		where f.value > 0

		insert into #fifo(fact_row_id, mfr_doc_id, product_id, d_fact, fact_q)
		select x.fact_row_id, x.mfr_doc_id, x.product_id, x.d_fact, x.value
		from @fact x
		where not exists(select 1 from #fifo where fact_row_id = x.fact_row_id)

		exec fifo_clear @fid

	-- checksum
		if @trace = 1			
			select 
				check_plan = [plan] - r_plan,
				check_fact = fact - r_fact
			from (
				select 
					cast((select sum(value) from #trace_plan) as decimal) as 'plan',
					cast((select sum(plan_q) from #fifo) as decimal) as 'r_plan',
					cast((select sum(value) from #trace_fact) as decimal) as 'fact',
					cast((select sum(fact_q) from #fifo) as decimal) as 'r_fact'
				) u

	-- save
		delete from mfr_r_planfact where version_id = @version_id

		insert into mfr_r_planfact(version_id, mfr_doc_id, product_id, d_plan, d_fact, plan_q, fact_q)
		select @version_id, mfr_doc_id, product_id, d_plan, d_fact, plan_q, fact_q
		from #fifo
		
    -- depends
        exec mfr_plan_rates_calc;3 @version_id = @version_id, @enforce = @enforce -- mfr_r_milestones
		exec mfr_plan_rates_calc;4 @version_id = @version_id, @enforce = @enforce -- mfr_r_places

	exec drop_temp_table '#trace_plan,#trace_fact,#fifo'
end
go
-- helper: calc mfr_r_milestones
create proc mfr_plan_rates_calc;3
	@version_id int = 0,
	@enforce bit = 0,
	@trace bit = 0
as
begin
	set nocount on;

	if @version_id = 0 and exists(select 1 from mfr_plans_vers)
		set @version_id = (select max(version_id) from mfr_plans_vers)

	declare @today date = dbo.today()
	declare @d_calc datetime = isnull((select top 1 d_calc from mfr_r_milestones where version_id = @version_id), '1900-01-01')
	if @enforce = 0 and datediff(minute, @d_calc, getdate()) < 5 
	begin
		print 'Register MFR_R_MILESTONES is actual. No calculation nedeed.'
		return
	end

	create table #ms_docs(id int primary key)
	insert into #ms_docs 
	-- select 1104
	select doc_id from mfr_sdocs where plan_status_id = 1 and status_id >= 0

	-- #ms_contents
		create table #ms_contents(
			mfr_doc_id int,
			product_id int,
			milestone_id int,
			content_id int,
			q_complect float,
			oper_id int index ix_oper,
			primary key (mfr_doc_id, milestone_id, content_id),
			index ix_join (content_id, milestone_id)
			)
		insert into #ms_contents(mfr_doc_id, product_id, milestone_id, content_id, q_complect, oper_id)
		select o.mfr_doc_id, o.product_id, o.milestone_id, o.content_id, 
			max(q_brutto_product / nullif(sp.quantity,0)),
			max(o.oper_id)
		from sdocs_mfr_opers o
			join #ms_docs i on i.id = o.mfr_doc_id
			join sdocs_mfr_contents c on c.content_id = o.content_id
			join sdocs_products sp on sp.doc_id = o.mfr_doc_id and sp.product_id = o.product_id
		where milestone_id is not null
			and sp.quantity > 0
		group by o.mfr_doc_id, o.product_id, o.milestone_id, o.content_id

	-- select * from #ms_contents where milestone_id = 30
	-- -- select * from sdocs_mfr_opers where oper_id = 4682565
	-- return

		exec sys_set_triggers 0
			update x set milestone_id = null
			from sdocs_mfr_opers x
				join #ms_contents o on o.content_id = x.content_id 
					and o.milestone_id = x.milestone_id
					and o.oper_id != x.oper_id
		exec sys_set_triggers 1

	-- #ms_contents_fact
		create table #ms_contents_fact(
			row_id int identity primary key,
			mfr_doc_id int,
			product_id int,
			milestone_id int,
			content_id int,
			d_fact date,
			fact_q float,
			fact_rq float,
			index ix1 (mfr_doc_id, milestone_id, content_id),
			index ix2 (content_id, d_fact)
			)

		-- детали
		insert into #ms_contents_fact(mfr_doc_id, product_id, milestone_id, content_id, d_fact, fact_q)
		select r.mfr_doc_id, c.product_id, c.milestone_id, r.content_id, 
			r.job_date,
			isnull(case when r.job_status_id = 100 then r.fact_q end / nullif(c.q_complect,0), 0)
		from v_mfr_r_plans_jobs_items_all r
			join #ms_contents c on c.oper_id = r.oper_id
		where r.job_date is not null
		order by r.mfr_doc_id, c.product_id, c.milestone_id, r.content_id, r.job_date

		-- кооперация / материалвы
		insert into #ms_contents_fact(mfr_doc_id, product_id, milestone_id, content_id, d_fact, fact_q)
		select r.mfr_doc_id, c.product_id, c.milestone_id, r.content_id, 
			r.d_to_fact,
			r.fact_q / nullif(c.q_complect,0)
		from sdocs_mfr_opers r
			join sdocs_mfr_contents rc on rc.content_id = r.content_id
			join #ms_contents c on c.oper_id = r.oper_id
		where rc.is_buy = 1
			and r.d_to_fact is not null
		order by r.mfr_doc_id, c.product_id, c.milestone_id, r.content_id, r.d_to_fact

	-- #ms_dates
		create table #ms_dates(
			mfr_doc_id int,
			milestone_id int,
			d_doc date,
			primary key (mfr_doc_id, milestone_id, d_doc)
			)
		insert into #ms_dates(mfr_doc_id, milestone_id, d_doc)
		select distinct mfr_doc_id, milestone_id, d_fact
		from #ms_contents_fact

		-- append #ms_dates
		insert into #ms_contents_fact(mfr_doc_id, product_id, milestone_id, content_id, d_fact, fact_q)
		select o.mfr_doc_id, o.product_id, o.milestone_id, o.content_id, d.d_doc, 0
		from #ms_contents o
			join #ms_dates d on d.mfr_doc_id = o.mfr_doc_id and d.milestone_id = o.milestone_id
		where not exists(
			select 1 from #ms_contents_fact 
			where content_id = o.content_id 
				and milestone_id = o.milestone_id 
				and d_fact = d.d_doc
			)

		insert into #ms_contents_fact(mfr_doc_id, product_id, milestone_id, content_id, d_fact, fact_q)
		select o.mfr_doc_id, o.product_id, o.milestone_id, o.content_id, @today, 0
		from #ms_contents o
		where not exists(select 1 from #ms_contents_fact where content_id = o.content_id and milestone_id = 30)

	-- fact_rq
		update x set fact_rq = rq
		from #ms_contents_fact x
			join (
				select
					row_id,
					rq = sum(fact_q) over (partition by content_id, milestone_id order by d_fact)
				from #ms_contents_fact
			) xx on xx.row_id = x.row_id

	-- select * from #ms_contents_fact where milestone_id = 30 order by content_id, d_fact
	-- return

	-- #ms_milestones
		create table #ms_milestones(
			row_id int identity primary key,
			mfr_doc_id int,
			product_id int,
			milestone_id int,
			d_fact date,
			fact_rq float,
			round_rq float,
			diff_rq float,
			index ix (mfr_doc_id, milestone_id, d_fact)
			)

		insert into #ms_milestones(mfr_doc_id, product_id, milestone_id, d_fact, fact_rq, round_rq)
		select mfr_doc_id, product_id, milestone_id, d_fact, min(fact_rq), min(cast(fact_rq as int))
		from #ms_contents_fact
		group by mfr_doc_id, product_id, milestone_id, d_fact

		-- diff_rq
			update x set diff_rq = round_rq - isnull(prev_rq,0)
			from #ms_milestones x
				join (
					select
						row_id,
						prev_rq = lag(round_rq, 1, null) over (partition by mfr_doc_id, product_id, milestone_id order by d_fact)
					from #ms_milestones
				) xx on xx.row_id = x.row_id

	-- select * from #ms_milestones where milestone_id = 30
	-- return

	-- plan + fact (FIFO)
		declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%Готовая продукция%')

		-- #ms_plan
			create table #ms_plan(
				plan_row_id int identity primary key,
				mfr_doc_id int,
				product_id int,
				milestone_id int,
				mfr_d_plan date,
				d_plan date,
				value float,
				index ix_join (mfr_doc_id, product_id, milestone_id)
				)
			
			insert into #ms_plan(mfr_doc_id, product_id, milestone_id, mfr_d_plan, d_plan, value)
			select mfr_doc_id, product_id, milestone_id, mfr_d_plan, max(d_plan), max(plan_q)
			from (
				select 
					o.mfr_doc_id, o.product_id, o.milestone_id, o.content_id,
					mfr_d_plan = pf.d_plan,
					d_plan = max(case when o.milestone_id = @attr_product then pf.d_plan else o.d_to_plan end),
					plan_q = cast(sum(o.plan_q
						* (pf.plan_q/nullif(sp.quantity,0) -- слои планов
						) / nullif(c.q_complect,0)) as decimal)
				from sdocs_mfr_opers o
					join #ms_contents c on c.oper_id = o.oper_id
					join mfr_r_planfact pf on 
								pf.version_id = @version_id 
							and pf.mfr_doc_id = o.mfr_doc_id 
							and pf.product_id = o.product_id
						join sdocs_products sp on sp.doc_id = pf.mfr_doc_id and sp.product_id = pf.product_id
				where o.d_to_plan is not null
					and pf.plan_q > 0
				group by o.mfr_doc_id, o.product_id, o.milestone_id, o.content_id, pf.d_plan
				) x 
			group by mfr_doc_id, product_id, milestone_id, mfr_d_plan
			order by mfr_doc_id, product_id, milestone_id, mfr_d_plan, max(d_plan)

	-- select * from #ms_plan where milestone_id = 30
	-- 	-- and mfr_doc_id = 1390988 order by plan_row_id
	-- return

		-- #ms_fact
			 create table #ms_fact(
				fact_row_id int identity primary key,
				mfr_doc_id int,
				product_id int,
				milestone_id int,
				d_fact date,
				value float,
				index ix (mfr_doc_id, product_id, milestone_id)
				)

			insert into #ms_fact(mfr_doc_id, product_id, milestone_id, d_fact, value)
			select mfr_doc_id, product_id, milestone_id, d_fact, diff_rq
			from #ms_milestones
			where diff_rq > 0
			order by mfr_doc_id, product_id, milestone_id, d_fact

	-- select * from #ms_fact where milestone_id = 30
	-- 	and mfr_doc_id = 1390988 order by fact_row_id
	-- return

		-- FIFO
			create table #ms_fifo(
				row_id int identity primary key,
				fact_row_id int index ix_f,
				plan_row_id int index ix_p,
				mfr_doc_id int,
				product_id int,
				milestone_id int,
				mfr_d_plan date,
				d_plan date,
				d_fact date,
				plan_q float,
				fact_q float
				)
			
			declare @fid uniqueidentifier set @fid = newid()

			insert into #ms_fifo(
				plan_row_id, fact_row_id,
				mfr_doc_id, product_id, milestone_id, mfr_d_plan, d_plan, d_fact,
				plan_q, fact_q
				)
			select
				r.plan_row_id, p.fact_row_id,
				r.mfr_doc_id, r.product_id, r.milestone_id, r.mfr_d_plan, r.d_plan, p.d_fact,
				f.value, f.value
			from #ms_plan r
				join #ms_fact p on p.mfr_doc_id = r.mfr_doc_id 
					and p.product_id = r.product_id
					and p.milestone_id = r.milestone_id
				cross apply dbo.fifo(@fid, p.fact_row_id, p.value, r.plan_row_id, r.value) f
			order by r.plan_row_id, p.fact_row_id

		-- reminds
			insert into #ms_fifo(
				plan_row_id, fact_row_id,
				mfr_doc_id, product_id, milestone_id, mfr_d_plan, d_plan, d_fact,
				plan_q, fact_q
				)
			select 
				r.plan_row_id, p.fact_row_id, 
				isnull(r.mfr_doc_id, p.mfr_doc_id),
				isnull(r.product_id, p.product_id),
				isnull(r.milestone_id, p.milestone_id),
				r.mfr_d_plan, r.d_plan, p.d_fact,
				f.rq_value, f.pv_value
			from dbo.fifo_reminds(@fid) f
				left join #ms_plan r on r.plan_row_id = f.rq_row_id
				left join #ms_fact p on p.fact_row_id = f.pv_row_id

		-- plan (not in)
			insert into #ms_fifo(plan_row_id, mfr_doc_id, product_id, milestone_id, mfr_d_plan, d_plan, plan_q)
			select x.plan_row_id, x.mfr_doc_id, x.product_id, x.milestone_id, x.mfr_d_plan, x.d_plan, x.value
			from #ms_plan x
			where not exists(select 1 from #ms_fifo where plan_row_id = x.plan_row_id)

		-- fact (not in)
			insert into #ms_fifo(fact_row_id, mfr_doc_id, product_id, milestone_id, d_plan, d_fact, fact_q)
			select x.fact_row_id, x.mfr_doc_id, x.product_id, x.milestone_id, x.d_fact, x.d_fact, x.value
			from #ms_fact x
			where not exists(select 1 from #ms_fifo where fact_row_id = x.fact_row_id)

			exec fifo_clear @fid

	-- select * from #ms_fifo where 
	-- 	mfr_doc_id = 1390988 and
	-- 	milestone_id = 30 order by mfr_d_plan, d_plan, d_fact
	-- return

		-- checksum
			if @trace = 1
				select 
					check_plan = [plan] - r_plan,
					check_fact = fact - r_fact
				from (
					select 
						cast((select sum(value) from #ms_plan) as decimal) as 'plan',
						cast((select sum(plan_q) from #ms_fifo) as decimal) as 'r_plan',
						cast((select sum(value) from #ms_fact) as decimal) as 'fact',
						cast((select sum(fact_q) from #ms_fifo) as decimal) as 'r_fact'
					) u
					
	-- save mfr_r_milestones
		delete from mfr_r_milestones where version_id = @version_id
		insert into mfr_r_milestones(version_id, mfr_doc_id, product_id, milestone_id, mfr_d_plan, d_plan, d_fact, plan_q, fact_q)
		select @version_id, mfr_doc_id, product_id, milestone_id, mfr_d_plan, d_plan, d_fact, plan_q, fact_q
		from #ms_fifo

	-- append for consistency
		insert into mfr_r_milestones(version_id, mfr_doc_id, product_id, milestone_id, mfr_d_plan, d_plan, d_fact, plan_q, fact_q, slice)
		select @version_id, mfr_doc_id, product_id, @attr_product, d_plan, d_plan, d_fact, plan_q, fact_q, 'problem'
		from mfr_r_planfact x
		where version_id = @version_id
			and not exists(select 1 from mfr_r_milestones where mfr_doc_id = x.mfr_doc_id and milestone_id = @attr_product)

    exec drop_temp_table '#ms_docs,#ms_contents,#ms_contents_fact,#ms_dates,#ms_milestones,#ms_plan,#ms_fact,#ms_fifo'
end
go
-- helper: calc mfr_r_places
create proc mfr_plan_rates_calc;4
	@version_id int = 0,
    @place_id int = null,
    @enforce bit = 0,
	@trace bit = 0
as
begin
	set nocount on;

	if @version_id = 0
		set @version_id = (select max(version_id) from mfr_plans_vers)

    -- set @place_id = 507

	-- dates
		declare @d_doc date = (select d_doc from mfr_plans_vers where version_id = @version_id)
		declare @d_from date = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)
		declare @d_to date = dateadd(d, -1, dateadd(m, 1, @d_from))
        declare @d_from_prev date = dateadd(d, -1, @d_from)
        declare @d_to_next date = dateadd(d, 1, @d_to)
    -- @enforce
        declare @today date = dbo.today()
        declare @d_calc datetime = isnull(
            (select top 1 d_calc from mfr_r_places where version_id = @version_id and @place_id is null or place_id = @place_id),
            '1900-01-01'
            )
        if @enforce = 0 and datediff(minute, @d_calc, getdate()) < 20
        begin
            print 'Register MFR_R_PLACES is actual. No calculation nedeed.'
            return
        end
    -- #ms_docs
        create table #ms_docs(id int primary key)
        insert into #ms_docs 
            -- select 613011
            select distinct mfr_doc_id from mfr_r_plans_jobs_items
            where mfr_doc_id is not null
	-- #ms_contents
		create table #ms_contents(
			mfr_doc_id int,
			product_id int,
			place_id int,
			content_id int,
			q_complect float,
			q_complects float,
			oper_id int index ix_oper,
			primary key (mfr_doc_id, place_id, content_id),
			index ix_join (content_id, place_id)
			)
		insert into #ms_contents(mfr_doc_id, product_id, place_id, content_id, q_complects, q_complect, oper_id)
		select 
            mfr_doc_id, product_id, place_id, content_id, 
            q_brutto_product / nullif(q_complect,0),
            q_complect, oper_id
        from (
            select o.mfr_doc_id, o.product_id, o.place_id, o.content_id, 
                q_brutto_product = max(q_brutto_product),
                q_complect = max(q_brutto_product / nullif(sp.quantity,0)),
                oper_id = max(o.oper_id)
            from sdocs_mfr_opers o
                join #ms_docs i on i.id = o.mfr_doc_id
                join sdocs_mfr_contents c on c.content_id = o.content_id
                join sdocs_products sp on sp.doc_id = o.mfr_doc_id and sp.product_id = o.product_id
            where 
                (@place_id is null or o.place_id = @place_id)
                and o.place_id is not null
                and sp.quantity > 0
                and c.is_buy = 0
            group by o.mfr_doc_id, o.product_id, o.place_id, o.content_id
            ) x

        -- select * from #ms_contents where content_id = 109749099
        -- return
	-- #ms_contents_fact
		create table #ms_contents_fact(
			row_id int identity primary key,
			mfr_doc_id int,
			product_id int,
			place_id int,
			content_id int,
			d_fact date,
			fact_q float,
			fact_rq float,
			index ix1 (mfr_doc_id, place_id, content_id),
			index ix2 (content_id, d_fact)
			)

		-- детали (< @d_from)
        
		insert into #ms_contents_fact(mfr_doc_id, product_id, place_id, content_id, d_fact, fact_q)
		select mfr_doc_id, product_id, place_id, content_id, d_fact, isnull(fact_q,0)
        from (
            select 
                r.mfr_doc_id, c.product_id, c.place_id, r.content_id, 
                d_fact = @d_from_prev,
                fact_q = sum(case when r.job_status_id = 100 then r.fact_q end / nullif(c.q_complect,0))
            from mfr_r_plans_jobs_items r
                join #ms_contents c on c.oper_id = r.oper_id
            where r.job_date <= @d_from_prev
            group by r.mfr_doc_id, c.product_id, c.place_id, r.content_id
        
            -- детали (@d_from .. @d_to)
            union all
            select 
                r.mfr_doc_id, c.product_id, c.place_id, r.content_id, 
                r.job_date,
                case when r.job_status_id = 100 then r.fact_q end / nullif(c.q_complect,0)
            from mfr_r_plans_jobs_items r
                join #ms_contents c on c.oper_id = r.oper_id
            where r.job_date between @d_from and @d_to
            ) x
		order by mfr_doc_id, product_id, place_id, content_id, d_fact

        -- select * from #ms_contents_fact where content_id = 109749099
        -- return
	-- #ms_dates
		create table #ms_dates(
			mfr_doc_id int,
			place_id int,
			d_doc date,
			primary key (mfr_doc_id, place_id, d_doc)
			)
		insert into #ms_dates(mfr_doc_id, place_id, d_doc)
		select distinct mfr_doc_id, place_id, d_fact
		from #ms_contents_fact

		-- append #ms_dates
		insert into #ms_contents_fact(mfr_doc_id, product_id, place_id, content_id, d_fact, fact_q)
		select o.mfr_doc_id, o.product_id, o.place_id, o.content_id, d.d_doc, 0
		from #ms_contents o
			join #ms_dates d on d.mfr_doc_id = o.mfr_doc_id and d.place_id = o.place_id
		where not exists(
			select 1 from #ms_contents_fact 
			where content_id = o.content_id 
				and place_id = o.place_id 
				and d_fact = d.d_doc
			)
        
        -- select * from #ms_dates
        -- return
	-- fact_rq
		update x set fact_rq = rq
		from #ms_contents_fact x
			join (
				select
					row_id,
					rq = sum(fact_q) over (partition by content_id, place_id order by d_fact)
				from #ms_contents_fact
			) xx on xx.row_id = x.row_id

        -- select * from #ms_contents_fact 
        -- order by content_id, place_id, d_fact
        -- return
	-- #ms_places
		create table #ms_places(
			row_id int identity primary key,
			mfr_doc_id int,
			product_id int,
			place_id int,
			d_fact date,
			fact_rq float,
			round_rq float,
			diff_rq float,
			index ix (mfr_doc_id, place_id, d_fact)
			)

		insert into #ms_places(mfr_doc_id, product_id, place_id, d_fact, fact_rq, round_rq)
		select mfr_doc_id, product_id, place_id, d_fact, min(fact_rq), min(cast(fact_rq as decimal(18,4)))
		from #ms_contents_fact
		group by mfr_doc_id, product_id, place_id, d_fact

		-- diff_rq
			update x set diff_rq = round_rq - isnull(prev_rq,0)
			from #ms_places x
				join (
					select
						row_id,
						prev_rq = lag(round_rq, 1, null) over (partition by mfr_doc_id, place_id order by d_fact)
					from #ms_places
				) xx on xx.row_id = x.row_id
        
        -- select * from #ms_places
        -- return
    -- plan + fact (FIFO)
		-- #ms_plan
			create table #ms_plan(
				plan_row_id int identity primary key,
				mfr_doc_id int,
				product_id int,
				place_id int,
				mfr_d_plan date,
				d_plan date,
				value float,
				index ix_join (mfr_doc_id, product_id, place_id)
				)
			
			insert into #ms_plan(mfr_doc_id, product_id, place_id, mfr_d_plan, d_plan, value)
			select 
                mfr_doc_id, product_id, place_id, mfr_d_plan, max(d_plan), max(plan_q)
			from (
				select
                    mfr_doc_id, product_id, place_id, mfr_d_plan, 
                    d_plan = 
                        case 
                            when d_plan < @d_from then @d_from_prev 
                            when d_plan > @d_to then @d_to_next
                            else d_plan 
                        end,
                    plan_q = plan_q
                from (
                    select 
                        o.mfr_doc_id, o.product_id, o.place_id, o.content_id,
                        mfr_d_plan = pf.d_plan,
                        d_plan = max(o.d_to_plan),
                        plan_q = cast(sum(o.plan_q
                            * (pf.plan_q/nullif(sp.quantity,0) -- слои планов
                            ) / nullif(c.q_complect,0)) as decimal)
                    from sdocs_mfr_opers o
                        join #ms_contents c on c.oper_id = o.oper_id
                        join mfr_r_planfact pf on 
                                    pf.version_id = @version_id 
                                and pf.mfr_doc_id = o.mfr_doc_id 
                                and pf.product_id = o.product_id
                            join sdocs_products sp on sp.doc_id = pf.mfr_doc_id and sp.product_id = pf.product_id
                    where o.d_to_plan is not null
                        and pf.plan_q > 0
                    group by o.mfr_doc_id, o.product_id, o.place_id, o.content_id, pf.d_plan
                    ) x
				) x 
			group by mfr_doc_id, product_id, place_id, mfr_d_plan
			order by mfr_doc_id, product_id, place_id, mfr_d_plan, max(d_plan)
		-- #ms_fact
			 create table #ms_fact(
				fact_row_id int identity primary key,
				mfr_doc_id int,
				product_id int,
				place_id int,
				d_fact date,
				value float,
				index ix (mfr_doc_id, product_id, place_id)
				)

			insert into #ms_fact(mfr_doc_id, product_id, place_id, d_fact, value)
			select mfr_doc_id, product_id, place_id, d_fact, diff_rq
			from #ms_places
			where diff_rq > 0
			order by mfr_doc_id, product_id, place_id, d_fact

            -- select * from #ms_places
            -- return

		-- FIFO
			create table #ms_fifo(
				row_id int identity primary key,
				fact_row_id int index ix_f,
				plan_row_id int index ix_p,
				mfr_doc_id int,
				product_id int,
				place_id int,
				mfr_d_plan date,
				d_plan date,
				d_fact date,
				plan_q float,
				fact_q float
				)
			
			declare @fid uniqueidentifier set @fid = newid()

			insert into #ms_fifo(
				plan_row_id, fact_row_id,
				mfr_doc_id, product_id, place_id, mfr_d_plan, d_plan, d_fact,
				plan_q, fact_q
				)
			select
				r.plan_row_id, p.fact_row_id,
				r.mfr_doc_id, r.product_id, r.place_id, r.mfr_d_plan, r.d_plan, p.d_fact,
				f.value, f.value
			from #ms_plan r
				join #ms_fact p on p.mfr_doc_id = r.mfr_doc_id 
					and p.product_id = r.product_id
					and p.place_id = r.place_id
				cross apply dbo.fifo(@fid, p.fact_row_id, p.value, r.plan_row_id, r.value) f
			order by r.plan_row_id, p.fact_row_id
		-- reminds
			insert into #ms_fifo(
				plan_row_id, fact_row_id,
				mfr_doc_id, product_id, place_id, mfr_d_plan, d_plan, d_fact,
				plan_q, fact_q
				)
			select 
				r.plan_row_id, p.fact_row_id, 
				isnull(r.mfr_doc_id, p.mfr_doc_id),
				isnull(r.product_id, p.product_id),
				isnull(r.place_id, p.place_id),
				r.mfr_d_plan, r.d_plan, p.d_fact,
				f.rq_value, f.pv_value
			from dbo.fifo_reminds(@fid) f
				left join #ms_plan r on r.plan_row_id = f.rq_row_id
				left join #ms_fact p on p.fact_row_id = f.pv_row_id
		-- plan (not in)
			insert into #ms_fifo(plan_row_id, mfr_doc_id, product_id, place_id, mfr_d_plan, d_plan, plan_q)
			select x.plan_row_id, x.mfr_doc_id, x.product_id, x.place_id, x.mfr_d_plan, x.d_plan, x.value
			from #ms_plan x
			where not exists(select 1 from #ms_fifo where plan_row_id = x.plan_row_id)
		-- fact (not in)
			insert into #ms_fifo(fact_row_id, mfr_doc_id, product_id, place_id, d_plan, d_fact, fact_q)
			select x.fact_row_id, x.mfr_doc_id, x.product_id, x.place_id, x.d_fact, x.d_fact, x.value
			from #ms_fact x
			where not exists(select 1 from #ms_fifo where fact_row_id = x.fact_row_id)

			exec fifo_clear @fid
		-- checksum
			if @trace = 1
				select 
					check_plan = [plan] - r_plan,
					check_fact = fact - r_fact
				from (
					select 
						cast((select sum(value) from #ms_plan) as decimal) as 'plan',
						cast((select sum(plan_q) from #ms_fifo) as decimal) as 'r_plan',
						cast((select sum(value) from #ms_fact) as decimal) as 'fact',
						cast((select sum(fact_q) from #ms_fifo) as decimal) as 'r_fact'
					) u
	-- save mfr_r_places
		delete from mfr_r_places where version_id = @version_id and (@place_id is null or place_id = @place_id)

		insert into mfr_r_places(version_id, mfr_doc_id, product_id, place_id, mfr_d_plan, d_plan, d_fact, plan_q, fact_q)
		select @version_id, mfr_doc_id, product_id, place_id, mfr_d_plan, d_plan, d_fact, plan_q, fact_q
		from #ms_fifo

    exec drop_temp_table '#ms_docs,#ms_contents,#ms_contents_fact,#ms_dates,#ms_places,#ms_plan,#ms_fact,#ms_fifo'
end
go

-- exec mfr_plan_rates_calc 1000
-- exec mfr_plan_rates_calc;2 @enforce = 1, @trace = 1
-- exec mfr_plan_rates_calc;3 @enforce = 1, @trace = 1
-- exec mfr_plan_rates_calc;4 @enforce = 1, @trace = 1
