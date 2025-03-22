if object_id('mfr_reps_equipments') is not null drop proc mfr_reps_equipments
go
-- exec mfr_reps_equipments 1000, @folder_id = -1
create proc mfr_reps_equipments
	@mol_id int,
	@d_from date = null,
	@d_to date = null,
	@folder_id int = null,
	@context varchar(20) = 'plans' -- plans, docs, contents, jobs, jobs-queue
as
begin
	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -- @docs
        declare @docs as app_pkids
        insert into @docs select doc_id from mfr_sdocs where plan_status_id = 1

    -- params
        declare @today date = dbo.today()
        if @d_from is null 
        begin
            set @d_from = dateadd(d, -datepart(d, @today) + 1, @today)
            set	@d_to = dateadd(d, -1, dateadd(m, 1, @d_from))
        end

        if @d_to is null set @d_to = @today

        create table #work_types(work_type_id int primary key, name varchar(50))
            insert into #work_types values 
                (1, 'Производство'),
                (2, 'Закупка'),
                (3, 'Кооперация')

    -- buffer
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

        create table #contents(id int primary key)
        create table #opers(id int primary key)
        
        if @context = 'plans' 
            insert into #opers
            select x.oper_id
            from sdocs_mfr_opers x
                join sdocs_mfr_contents c on c.content_id = x.content_id
                    join mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = x.number
                        join mfr_drafts_opers_resources dr on dr.draft_id = do.draft_id and dr.oper_id = do.oper_id
                left join #work_types wt on wt.work_type_id = x.work_type_id
            where c.mfr_doc_id in (select id from @docs)
                and isnull(x.d_to_fact, x.d_to_plan) between @d_from and @d_to

        else if @context = 'contents'
            insert into #contents exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfc'

        else if @context = 'docs'
        begin
            set @context = 'contents'

            delete from @docs
            insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'

            insert into #contents
            select content_id from sdocs_mfr_contents where mfr_doc_id in (select id from @docs)
        end

        else if @context = 'jobs'
        begin
            set @context = 'contents'

            declare @jobs as app_pkids
            insert into @jobs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfj'

            insert into #contents
            select distinct content_id
            from mfr_r_plans_jobs_items
            where job_id in (select id from @jobs)
                and content_id is not null
        end

        else if @context = 'jobs-queue'
        begin
            set @context = 'opers'

            declare @jqueue as app_pkids
            insert into @jqueue exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mco'

            insert into #opers
            select distinct x.oper_id
            from mfr_plans_jobs_queues x
                join @jqueue i on i.id = x.detail_id
            where x.oper_id is not null
        end

        if not exists(select 1 from #opers) 
        begin
            insert into #opers(id)
            select oper_id from sdocs_mfr_opers o
                join #contents c on c.id = o.content_id
            drop table #contents
        end

    -- #result
        select 
            do.place_id, c.mfr_doc_id, c.product_id, c.item_id, oper_status_id = x.status_id,
            d_doc = cast(x.d_from_plan as date),
            dr.resource_id,
            work_type_name = isnull(wt.name, '-'),
            quantity = isnull(x.fact_q, x.plan_q),
            loading = isnull(x.fact_q, x.plan_q) * dr.loading,
            loading_limit = cast(null as float),
            loading_cost = dr.loading_price * c.q_brutto_product
        into #result
        from sdocs_mfr_opers x
            join #opers i on i.id = x.oper_id
            join sdocs_mfr_contents c on c.content_id = x.content_id
                join mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = x.number
                    join mfr_drafts_opers_resources dr on dr.draft_id = do.draft_id and dr.oper_id = do.oper_id
            left join #work_types wt on wt.work_type_id = x.work_type_id

        create index ix_group on #result(place_id, mfr_doc_id, product_id, item_id, resource_id, d_doc)

        insert into #result(place_id, resource_id, loading_limit, work_type_name)
        select x.place_id, x.resource_id, rs.quantity * rs.loading, '-'
        from (
            select distinct place_id, resource_id from #result
            ) x
            join mfr_places_equipments rs on rs.place_id = x.place_id and rs.resource_id = x.resource_id

    -- select
        select 
            PlaceName = pl.full_name,
            MfrNumber = mfr.number,
            ProductName = p1.name,
            ItemName = p2.name,
            WorkTypeName = r.work_type_name,
            OperStatusName = st.name,
            ResourceName = rs.name,
            DateFromPlan = r.d_doc,
            Quantity = r.quantity,
            Loading = r.loading,
            LoadingLimit = r.loading_limit,
            LoadingCost = r.loading_cost
        from (
            select 
                place_id, mfr_doc_id, product_id, item_id, oper_status_id, resource_id, d_doc, work_type_name,
                quantity = sum(quantity),
                loading = sum(loading),
                loading_limit = sum(loading_limit),
                loading_cost = sum(loading_cost)
            from #result
            group by
                place_id, mfr_doc_id, product_id, item_id, oper_status_id, resource_id, d_doc, work_type_name
            ) r
            join mfr_places pl on pl.place_id = r.place_id
            join mfr_resources rs on rs.resource_id = r.resource_id
            left join mfr_items_statuses st on st.status_id = r.oper_status_id
            left join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
            left join products p1 on p1.product_id = r.product_id
            left join products p2 on p2.product_id = r.item_id

        exec drop_temp_table '#contents,#opers,#result'
end
GO
