if object_id('mfr_print_opers_pf') is not null drop proc mfr_print_opers_pf
go
-- exec mfr_print_opers_pf 1000, @plan_id = 0, @place_id = 510
-- exec mfr_print_opers_pf 1000, @plan_id = 0, @folder_id = 71816
create proc mfr_print_opers_pf
	@mol_id int,
	@place_id int,
	@plan_id int = null,
	@folder_id int = null, -- папка сменных заданий
	@mfr_doc_id int = null,
	@d_doc datetime = null,
	@search varchar(max) = null,
	@extra_id int = null,
        -- 1 не сделано
    @recalc bit = 0,
    @trace bit = 0
as
begin
	set nocount on;

	declare @today date = dbo.today()

	-- #plans, #contents
		create table #plans(id int primary key)
		create table #contents(id int primary key)

		if @folder_id is not null set @plan_id = 0
		set @place_id = nullif(@place_id, 0)
		
		if @plan_id = 0 insert into #plans select plan_id from mfr_plans where status_id = 1
		else if @plan_id is not null insert into #plans select @plan_id
		
		if @folder_id is not null
			insert into #contents exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfc'

		declare @filter_contents bit = case when exists(select 1 from #contents) then 1 end

		set @d_doc = isnull(@d_doc, @today)
		declare @d_from date = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)
		declare @d_to date = dateadd(d, -1, dateadd(m, 1, @d_from))
		declare @d_from_prev date = dateadd(d, -1, @d_from)
	-- reglament access
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key);	insert into #subjects select distinct obj_id from @objects where obj_type = 'sbj'

    exec mfr_plan_jobs_calc_place @place_id = @place_id, @enforce = @recalc

	-- #result
    select 
        x.*,
        RowId = row_number() over (order by MfrNumber),
        PeriodFrom = @d_from,
        PeriodTo = @d_to,
        DateTo = x.DateToPlan,
        GroupName = 
            case 				
                when x.DateToPlan < @d_from and isnull(x.DateToFact, @d_from) >= @d_from then '1-Недодел прошлого периода'
                else '2-Детали текущего периода'
            end,
        ProductName = p.name,
        ItemName = pi.name,
        PlanQ = x.CalcPlanQ - isnull(x.FactPrevQ,0),
        ItemCompleted = case when x.FactQ >= x.CalcPlanQ - isnull(x.FactPrevQ,0) then 1 else 0 end,
        JobStatusId = st.status_id,
        JobStatusName = st.short_name,
        JobStatusNote = st.name,
        JobStatusCss = st.css,
        JobStatusStyle = st.style
    into #result
    from (
        select 
            MfrNumber = mfr.number,
            MfrPriority = mfr.priority_id,
            MfrPriorityCss = prio.css,
            MfrCompleted = cast(case when mfr.status_id = 100 then 1 else 0 end as bit),
            DateDelivery = mfr.d_delivery,
            DateToPlan = r.d_plan,
            DateToFact = r.d_fact,
            CalcPlanQ = r.plan_q,
            PlanNextQ = r.plan_next_q,
            FactPrevQ = r.fact_prev_q,
            FactQ = r.fact_q,
            r.content_id,
            r.status_id
        from (
            select 
                mfr_doc_id, content_id, status_id, d_plan, d_fact,
                plan_q = sum(plan_q),
                plan_next_q = sum(plan_next_q),
                fact_q = sum(fact_q),
                fact_prev_q = sum(fact_prev_q)
            from (
                select 
                    mfr_doc_id, content_id, status_id,
                    d_plan = case when d_plan >= @d_from then d_plan else @d_from_prev end,
                    d_fact = case when d_fact < @d_from then @d_from_prev else d_fact end,
                    plan_q = case when d_plan <= @d_to then plan_q end,
                    plan_next_q = case when d_plan > @d_to then plan_q end,
                    fact_q = case when d_fact between @d_from and @d_to then fact_q end,
                    fact_prev_q = case when d_fact < @d_from then fact_q end
                from mfr_r_plans_jobs_items_facts
                where place_id = @place_id
                ) r
            group by mfr_doc_id, content_id, status_id, d_plan, d_fact
            ) r
            join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
                left join mfr_sdocs_priorities prio on mfr.priority_id between prio.priority_id and prio.priority_max
        where 
            -- reglament access
            mfr.subject_id in (select id from #subjects)
            -- conditions
            and mfr.plan_id in (select id from #plans)
            and (@mfr_doc_id is null or r.mfr_doc_id = @mfr_doc_id)
            and (@filter_contents is null or r.content_id in (select id from #contents))
        ) x
        join sdocs_mfr_contents c on c.content_id = x.content_id
            join products p on p.product_id = c.product_id
            join products pi on pi.product_id = c.item_id
        left join mfr_items_statuses st on st.status_id = x.status_id
    where (@search is null or pi.name like '%' + @search + '%')
        -- conditions
        and (
            isnull(@filter_contents,0) = 1
            or (
            -- Факт(до) в периоде и <= Сегодня
            x.DateToFact between @d_from and @d_to and x.DateToFact <= @d_doc
            or (
                    x.DateToPlan <= @d_to
                    and isnull(x.DateToFact, @d_from) between @d_from and @d_doc
                )
            )
        )

    create index ix_content on #result(content_id)
    
    create table #result_contents(
        content_id int primary key, 
        MaterialProvided float,
        WorkCompleted float
        )
    insert into #result_contents(content_id) select distinct content_id from #result

    -- MaterialProvided
		update x set 
			MaterialProvided = sum_provided / nullif(sum_materials,0)
        from #result_contents x
            join (
                select c.content_id, 
                    sum_materials = sum(cm.q_brutto_product * cm.item_price0),
                    sum_provided = sum(cm.q_provided_max * cm.item_price0)
                from sdocs_mfr_contents c
                    join sdocs_mfr_contents cm with(nolock) on cm.mfr_doc_id = c.mfr_doc_id and cm.product_id = c.product_id
                        and cm.node.IsDescendantOf(c.node) = 1
                        and cm.is_buy = 1
                group by c.content_id
            ) c on c.content_id = x.content_id
		
        update #result_contents set MaterialProvided = 1 where MaterialProvided >= 0.99999

    -- WorkCompleted
		update x set 
			WorkCompleted = duration_wk_completed / nullif(duration_wk_all,0)
        from #result_contents x
    		join (
				select
					o.content_id,
                    duration_wk_completed = sum(case when o.status_id = 100 then o.duration_wk * dur.factor / dur_h.factor end),
                    duration_wk_all = sum(o.duration_wk * dur.factor / dur_h.factor)
				from sdocs_mfr_opers o with(nolock)
                    join projects_durations dur on dur.duration_id = o.duration_wk_id
                    join projects_durations dur_h on dur_h.duration_id = 2
				where o.place_id = @place_id
				group by o.content_id
			) xx on xx.content_id = x.content_id

        update #result_contents set WorkCompleted = 1 where WorkCompleted >= 0.99999

    -- adjust
        update #result_contents set MaterialProvided = 1 where WorkCompleted = 1

    select
        r.*,
        MaterialProvided = c.MaterialProvided * 100,
        WorkCompleted = c.WorkCompleted * 100
    from #result r
        join #result_contents c on c.content_id = r.content_id
    where (
        @extra_id is null
        or (@extra_id = 1 and JobStatusId != 100)
        )

	final:
		exec drop_temp_table '#subjects,#plans,#contents,#result'
end
GO
