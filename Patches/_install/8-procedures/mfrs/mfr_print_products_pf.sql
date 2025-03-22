if object_id('mfr_print_products_pf') is not null drop proc mfr_print_products_pf
go
-- exec mfr_print_products_pf 1000, @plan_id = 0, @search = 'EB2303078.139348.84919'
create proc mfr_print_products_pf
	@mol_id int,
	@plan_id int = null,
	@folder_id int = null, -- папка заказов
	@version_id int = 0,
	@d_doc datetime = null,
	@hide_outofplan bit = 1,
	@hide_completed bit = 0,
	@search varchar(max) = null,
    @trace bit = 0
as
begin
	set nocount on;

    declare @today date = dbo.today()

	if @version_id = 0 and exists(select 1 from mfr_plans_vers)
		set @version_id = (select max(version_id) from mfr_plans_vers)

	set @search = '%' + replace(@search, ' ', '%') + '%'

	-- #plans, #docs
		create table #plans(id int primary key)
		create table #docs(id int primary key)

		if @folder_id is not null set @plan_id = null

		if @plan_id = 0 
			insert into #plans select plan_id from mfr_plans where status_id = 1

		else if @plan_id is not null
			insert into #plans select @plan_id
		
		else begin
			set @folder_id = isnull(@folder_id, dbo.objs_buffer_id(@mol_id))
			insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
		end

	-- reglament access
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key);	insert into #subjects select distinct obj_id from @objects where obj_type = 'sbj'

		declare @subject_id int = (select subject_id from mfr_plans where plan_id = @plan_id)
		declare @is_commerce bit = case when dbo.isinrole_byobjs(@mol_id, 'Mfr.Commerce', 'SBJ', @subject_id) = 1 then 1 end

	-- dates
		set @d_doc = isnull(@d_doc, dbo.today())
		declare @d_from date = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)
		declare @d_to date = dateadd(d, -1, dateadd(m, 1, @d_from))

	-- tables
		declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%Готовая продукция%')
		create table #milestones(
			mfr_doc_id int index ix_doc,
			agent_name varchar(250),
            product_id int,
            product_name varchar(500),
            product_value_ccy float,
            product_value_price float,
            -- 
			milestone_id int,
			milestone_name varchar(150),
			milestone_status varchar(250),
			milestone_value_work decimal(18,2),
            -- 
			d_to date,
			d_to_plan date,
			d_to_predict date,
			d_to_fact date,
			plan_q float,
			fact_q float,
			k_kd_completed float, -- % завершения конструкторской документации
			k_items_completed float, -- % завершения деталей передела (по трудоёмкости)
			k_materials_provided float, -- % обеспечения материалами
			index ix_sort (mfr_doc_id, product_id, milestone_name),
			index ix_join (mfr_doc_id, milestone_id)
			)

	-- Готовая продукция и НЗП
		insert into #milestones(
			mfr_doc_id, agent_name, product_id, product_name, milestone_id, milestone_name, milestone_status, milestone_value_work,
			d_to, d_to_plan, d_to_predict, d_to_fact, plan_q, fact_q
			)
		select
			r.mfr_doc_id,
            r.agent_name,
			r.product_id,
            r.product_name,
			r.milestone_id,
			r.milestone_name,
			cast(null as varchar(250)) as milestone_status,
			r.ratio_value as milestone_value_work,
			isnull(r.d_delivery, @d_from) as d_to,
			isnull(ms_d_to_plan, @d_to) as d_to_plan,
			coalesce(ms_d_to_predict, r.d_issue_forecast, @d_from) as d_to_predict,
			r.d_fact as d_to_fact,
			cast(r.plan_q as decimal),
			cast(r.fact_q as decimal)
		from (
			select r.*,
				sd.d_delivery,
				sd.d_issue_forecast,
                case when r.milestone_id = @attr_product then r.mfr_d_plan else ms.d_to_plan end as ms_d_to_plan,
				ms.d_to_predict as ms_d_to_predict,
				a.name as milestone_name,
                ag.name as agent_name,
                p.name as product_name,
				ms.ratio_value
			from mfr_r_milestones r with(nolock)
				join sdocs sd with(nolock) on sd.doc_id = r.mfr_doc_id
			        left join agents ag with(nolock) on ag.agent_id = sd.agent_id
				join sdocs_mfr_milestones ms with(nolock) on ms.doc_id = sd.doc_id and ms.product_id = r.product_id and ms.attr_id = r.milestone_id
					join mfr_attrs a with(nolock) on a.attr_id = ms.attr_id
			    join products p with(nolock) on p.product_id = r.product_id
			where r.version_id = @version_id
				and (r.milestone_id = @attr_product or ms.ratio_value > 0)
			) r
            join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
		where (@hide_completed = 0 or mfr.status_id != 100)
            and (
                (
                @folder_id is not null and r.mfr_doc_id in (select id from #docs)
                )
                or (
                    @folder_id is null 
                    and (
                        (r.d_fact between @d_from and @d_to) -- факт
                        or		
                        (r.ms_d_to_plan <= @d_to and isnull(r.d_fact, @d_from) between @d_from and @d_to) -- + "хвосты"
                        )
                    and (
                        @search is null
                        or mfr.number like @search
                        or r.agent_name like @search
                        or r.product_name like @search
                        )
                ))

    -- value_ccy, value_price
        if @is_commerce = 1 begin
            update x set 
                product_value_ccy = sp.value_ccy * x.plan_q / nullif(sp.quantity,0),
                product_value_price = sp.price_list * x.plan_q
            from #milestones x
                join sdocs_products sp on sp.doc_id = x.mfr_doc_id and sp.product_id = x.product_id
            where x.milestone_id = @attr_product;
        end;

    -- milestone_value_work
		update #milestones set d_to_fact = null where fact_q < plan_q
		
		update x set 
			milestone_value_work = milestone_value_work * x.plan_q / nullif(xx.plan_q,0)
		from #milestones x
			join (
				select mfr_doc_id = ms.doc_id, ms.product_id, milestone_name = a.name, plan_q = sp.quantity
				from sdocs_mfr_milestones ms
					join mfr_attrs a on a.attr_id = ms.attr_id
					join sdocs_products sp on sp.doc_id = ms.doc_id and sp.product_id = ms.product_id
			) xx on xx.mfr_doc_id = x.mfr_doc_id and xx.product_id = x.product_id and xx.milestone_name = x.milestone_name
	
    -- k_kd_completed
		update ms set k_kd_completed = pt.progress
		from #milestones ms
			join sdocs sd on sd.doc_id = ms.mfr_doc_id
				join projects_tasks pt on pt.task_id = sd.project_task_id
	
    -- k_materials_provided
		declare @k float
		update x set 
			@k = 
				case
					when ms.k_provided > 0.9999 then 1.
					else cast(cast(ms.k_provided as float) * 10000 as int) / 10000.
				end,
			k_materials_provided = @k
		from #milestones x
			join sdocs_mfr_milestones ms on ms.doc_id = x.mfr_doc_id and ms.product_id = x.product_id and ms.attr_id = x.milestone_id

    -- k_items_completed
        declare @exclude_types app_pkids
            insert @exclude_types select id from dbo.mfr_provides_excl_items(0)
            
            create table #items_types(type_id int primary key)
                insert into #items_types 
                select id from (
                    select distinct isnull(item_type_id,0) as id from sdocs_mfr_contents
                    ) x
                where not exists(select 1 from @exclude_types) or id not in (select id from @exclude_types)

		update x set 
			@k = 1.00 * duration_wk_completed / nullif(duration_wk_all,0),
			k_items_completed = cast(cast(case when @k > 0.99999 then 1. else @k end as float) * 100000 as int) / 100000.
		from #milestones x
			join (
				select
					o.mfr_doc_id, o.milestone_id,
                    duration_wk_completed = sum(case when cm.status_id = 100 or oo.status_id = 100 then oo.duration_wk * dur.factor / dur_h.factor end),
                    duration_wk_all = sum(oo.duration_wk * dur.factor / dur_h.factor)
				from sdocs_mfr_opers o with(nolock)
					join sdocs_mfr_contents c with(nolock) on c.content_id = o.content_id
						join sdocs_mfr_contents cm with(nolock) on cm.mfr_doc_id = c.mfr_doc_id and cm.product_id = c.product_id
							and cm.node.IsDescendantOf(c.node) = 1
							and cm.is_buy = 0
                            join #items_types itp on itp.type_id = isnull(cm.item_type_id,0)
						join sdocs_mfr_opers oo with(nolock) on oo.content_id = cm.content_id
                            join projects_durations dur on dur.duration_id = oo.duration_wk_id
                            join projects_durations dur_h on dur_h.duration_id = 2
				where o.milestone_id is not null
				group by o.mfr_doc_id, o.milestone_id
			) xx on xx.mfr_doc_id = x.mfr_doc_id and xx.milestone_id = x.milestone_id

	-- #result
		create table #result(
			RowId int identity,
			MfrDocId int index ix_doc,
			MfrNumber varchar(100),
			MfrPriority int,
			MfrPriorityCss varchar(100),
			AgentName varchar(250),
			DateShipPlan date, -- дата отгрузки по договору
			DateIssuePDO date, -- дата выпуска по графику ПДО
			DateIssueForecast date, -- дата выпуска (прогноз)
			DateIssue date, -- дата выпуска (факт)
			MilestoneName varchar(250),
			Group1Name varchar(250),
			Group2Name varchar(250),
			Group2Label varchar(500),
			ProductId int,
            ProductName varchar(500),
            ProductValueCcy float,
            ProductValuePrice float,
			PeriodFrom date,
			PeriodTo date,
			PlanQ float,
			FactQ float,
			PriceList decimal(18,2),
			ValueWork decimal(18,2),
			PercentKDCompleted float,
			PercentItemsCompleted float,
			PercentMaterialsProvided float,
            KDCompletedLag int,
            ItemsCompletedLag int,
            ItemsCompletedLead int,
            MaterialsProvidedLag int,
            MaterialsProvidedLead int,
			MfrDocHid varchar(30)
			)

		insert into #result(
			MfrDocId, MfrNumber, MfrPriority, MfrPriorityCss,
			AgentName,
			DateShipPlan, DateIssuePDO, DateIssue, DateIssueForecast,
			MilestoneName, Group2Name, ProductId, ProductName, ProductValueCcy, ProductValuePrice,
			PlanQ, FactQ,
			ValueWork, PercentKDCompleted, PercentItemsCompleted, PercentMaterialsProvided,
			MfrDocHid
			)
		select
			sd.doc_id,
			sd.number,
			sd.priority_id,
            prio.css,
            case
                when x.milestone_name like '%Готовая продукция%' then x.agent_name
                else concat(x.agent_name, ' ', x.product_name)
            end as AgentName,
			x.d_to as DateShipPlan,
			x.d_to_plan as DateIssuePDO,
			x.d_to_fact as DateIssue,
			x.d_to_predict as DateIssueForecast,
            x.milestone_name as MilestoneName,
            case
                when x.d_to_plan < @d_from and isnull(x.d_to_fact, @d_from) >= @d_from then '1-Недодел прошлого периода'
                else '2-Текущий период'
            end as Group2Name,
			x.product_id as ProductId,
            case
                when x.milestone_name like '%Готовая продукция%' then x.product_name
                else x.milestone_name
            end as ProductName,
            x.product_value_ccy as ProductValueCcy,
            x.product_value_price as ProductValuePrice,
			x.plan_q as PlanQ,
			x.fact_q as FactQ,
			case when @is_commerce = 1 then x.milestone_value_work end as ValueWorkPlan,
			floor(cast(x.k_kd_completed * 100 as decimal(15,4))) as PercentKDCompleted,
			floor(cast(x.k_items_completed * 100 as decimal(15,4))) as PercentItemsCompleted,
			floor(cast(x.k_materials_provided * 100 as decimal(15,4))) as PercentMaterialsProvided,
			concat('#', sd.doc_id) as MfrDocHid
		from #milestones x
			join sdocs sd with(nolock) on sd.doc_id = x.mfr_doc_id
                left join mfr_sdocs_priorities prio on sd.priority_id between prio.priority_id and prio.priority_max
			join sdocs_products sp with(nolock) on sp.doc_id = sd.doc_id and sp.product_id = x.product_id;

    -- KDCompletedLag
		update x set KDCompletedLag = kd.d_diff
		from #result x
			join (
                select mfr_doc_id, d_diff = max(d_diff)
                from v_mfr_print_kd_diffs
                group by mfr_doc_id
            ) kd on kd.mfr_doc_id = x.mfrdocid;

    -- ItemsCompletedLag
        update x set ItemsCompletedLag = abs(xx.diff)
        from #result x
            join (
                select o.mfr_doc_id, diff = max(datediff(d, o.d_to_plan, isnull(o.d_to_fact, @today)))
                from sdocs_mfr_opers o
                    join sdocs_mfr_contents c on c.content_id = o.content_id
                        join #items_types itp on itp.type_id = isnull(c.item_type_id,0)
                where c.is_buy = 0
                    and o.d_to_plan < isnull(o.d_to_fact, @today)
                group by o.mfr_doc_id
            ) xx on xx.mfr_doc_id = x.MfrDocId

    -- ItemsCompletedLead
        update x set ItemsCompletedLead = abs(xx.diff)
        from #result x
            join (
                select o.mfr_doc_id, diff = min(datediff(d, o.d_to_plan, o.d_to_fact))
                from sdocs_mfr_opers o
                    join sdocs_mfr_contents c on c.content_id = o.content_id
                        join #items_types itp on itp.type_id = isnull(c.item_type_id,0)
                where c.is_buy = 0
                    and o.d_to_plan > o.d_to_fact
                group by o.mfr_doc_id
            ) xx on xx.mfr_doc_id = x.MfrDocId

    -- MaterialsProvidedLead
        delete from @exclude_types;
        insert @exclude_types select id from dbo.mfr_provides_excl_items(1);
        
        delete from #items_types;
        insert into #items_types
        select id from (
            select distinct isnull(item_type_id,0) as id from sdocs_mfr_contents
            ) x
        where not exists(select 1 from @exclude_types) or id not in (select id from @exclude_types);

        update x set MaterialsProvidedLead = abs(xx.diff)
        from #result x
            join (
                select r.mfr_doc_id, diff = min(datediff(d, r.d_mfr_to, r.d_job))
                from mfr_r_provides r
                    join sdocs_mfr_contents c on c.content_id = r.id_mfr and c.is_buy = 1
                        join #items_types itp on itp.type_id = isnull(c.item_type_id,0)
                where r.d_mfr_to > r.d_job
                    and r.xslice != 'manual'
                    and r.q_mfr >= 0.001
                group by r.mfr_doc_id
            ) xx on xx.mfr_doc_id = x.MfrDocId

    -- MaterialsProvidedLag
        update x set materialsprovidedlag = abs(xx.diff)
        from #result x
            join (
                select r.mfr_doc_id, diff = max(datediff(d, r.d_mfr_to, isnull(r.d_job, @today)))
                from mfr_r_provides r
                    join sdocs_mfr_contents c on c.content_id = r.id_mfr and c.is_buy = 1
                        join #items_types itp on itp.type_id = isnull(c.item_type_id,0)
                where r.d_mfr_to < isnull(r.d_job, @today)
                    and r.xslice != 'manual'
                    and r.q_mfr >= 0.001
                group by r.mfr_doc_id
            ) xx on xx.mfr_doc_id = x.MfrDocId

    -- Group1Name
        declare @group_name varchar(50) = isnull(dbo.app_registry_varchar('MfrRepProductGroup1Attr'), 'MfrTotalGrp')
        update x set
			Group1Name = 
				case
					when MilestoneName like '%Готовая продукция%' then isnull(g.name, '-')
					else 'НЗП'
				end
        from #result x
            left join (
                select product_id, attr_id = max(pa.attr_id)
                from products_attrs pa
                    join mfr_attrs a on a.attr_id = pa.attr_id and a.group_key = @group_name
                group by product_id
            ) pa on pa.product_id = x.ProductId
            left join mfr_attrs g on g.attr_id = pa.attr_id

		update #result set PeriodFrom = @d_from, PeriodTo = @d_to

		if @hide_outofplan = 1
			delete from #result where not DateIssuePDO between PeriodFrom and PeriodTo and DateIssue is null

		-- patches
			update #result set DateShipPlan = DateIssuePDO where DateShipPlan is null

	-- select
		select *,
			ValueWorkPDO = case when DateIssuePDO between PeriodFrom and PeriodTo then ValueWork end
		from #result

	exec drop_temp_table '#subjects,#plans,#docs,#milestones,#result'
end
GO

exec mfr_print_products_pf 1000, @plan_id = 0