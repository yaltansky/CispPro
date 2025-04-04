if object_id('mfr_reps_jobs_persons') is not null drop proc mfr_reps_jobs_persons
go
create proc mfr_reps_jobs_persons
	@mol_id int,
	@folder_id int = null, -- папка заказов
	@period_from datetime = null,
	@period_to datetime = null,
	@context varchar(50) = null -- docs, jobs, jobs-queue, contents
as
begin
    declare @period_days int = dbo.work_day_diff(@period_from, @period_to);
    declare @docs as app_pkids;
    declare @filter_jobs bit;
    declare @filter_contents bit;
    declare @filter_opers bit;

	set nocount on;
	set transaction isolation level read uncommitted;

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
		' @mol_id=', @mol_id,
		' @folder_id=', @folder_id,
		' @period_from=', @period_from,
		' @period_to=', @period_to
		)
	exec tracer_log @tid, @tid_msg

	exec tracer_log @tid, 'params'
		create table #jobs(id int primary key);
		create table #contents(id int primary key);
		create table #opers(id int primary key);

		if @folder_id is not null
		begin
			if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

            if @context = 'docs'
				insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
			
			else if @context = 'jobs' begin
                set @filter_jobs = 1
				insert into #jobs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfj'

				insert into @docs select distinct mfr_doc_id from mfr_plans_jobs_details
				where plan_job_id in (select id from #jobs) and mfr_doc_id > 0;
            end

			else if @context = 'jobs-queue' begin
				set @filter_opers = 1
				
				declare @jdetails app_pkids
				insert into @jdetails exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mco'
				
				insert into #opers select distinct oper_id
				from mfr_plans_jobs_queues x
					join @jdetails i on i.id = x.detail_id

				insert into @docs select distinct mfr_doc_id from sdocs_mfr_opers
				where oper_id in (select id from #opers)
			end
			
			else begin
				set @filter_contents = 1

				insert into #contents exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfc'

				insert into @docs select distinct mfr_doc_id from sdocs_mfr_contents
				where content_id in (select id from #contents)
			end
		end

		else if @period_from is not null begin
            set @filter_opers = 1

            insert into #opers select distinct oper_id
            from sdocs_mfr_opers x
            where x.d_to_plan between @period_from and @period_to;

            insert into @docs select distinct mfr_doc_id from sdocs_mfr_opers
            where oper_id in (select id from #opers)
        end

	create table #result(
		person_id int,
		person_name varchar(50),
		job_place_id int,
		job_status_id int,
		plan_job_id int,
		mfr_doc_id int index ix_mfr_doc,
		product_id int,
		item_id int,
		item_status_id int,
		oper_id int index ix_oper,
		oper_status_id int,
		oper_post_id int,
		oper_d_from_plan date,
		q_brutto_product float,
		norm_labor_hours float,
		labor_hours float,
		labor_hours_limit float,
		labor_persons_limit float,
        labor_persons_deficit float,
		index ix_join(job_place_id, oper_post_id, oper_d_from_plan)
		)

    if @period_from is null begin
        exec tracer_log @tid, 'labor_hours'
            insert into #result(
                person_id, person_name, 
                job_place_id, job_status_id, plan_job_id, mfr_doc_id, product_id, item_id, oper_id,
                labor_hours		
                )
            select
                mols.mol_id, mols.name,		
                x.job_place_id, x.job_status_id, x.job_id, x.mfr_doc_id, x.product_id, x.item_id, x.oper_id,
                case when x.job_status_id = 100 then x.job_hours end
            from (
                select 
                    job_place_id = j.place_id,
                    job_status_id = j.status_id,
                    job_id = j.plan_job_id,
                    job_date = cast(isnull(j.d_closed, j.d_doc) as date),
                    job_hours = e.duration_wk * dur.factor / dur_h.factor,
                    job_d_doc = j.d_doc,
                    jd.mfr_doc_id,
                    o.product_id,
                    jd.item_id,
                    o.content_id,
                    o.oper_id,
                    e.mol_id
                from mfr_plans_jobs_details jd
                    join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
                    join sdocs_mfr_opers o on o.oper_id = jd.oper_id
                    join mfr_plans_jobs_executors e on e.detail_id = jd.id
                        join projects_durations dur on dur.duration_id = e.duration_wk_id
                        join projects_durations dur_h on dur_h.duration_id = 2
                ) x
                left join mols on mols.mol_id = x.mol_id		
            where (x.mfr_doc_id in (select id from @docs))
                and (@filter_jobs is null or job_id in (select id from #jobs))
                and (@filter_contents is null or content_id in (select id from #contents))
                and (@filter_opers is null or oper_id in (select id from #opers))

            declare @costs table(doc_id int primary key, status_id int, cost_value float)
                insert into @costs(doc_id, status_id, cost_value)
                select x.doc_id, sd.status_id, sum(ratio_value)
                from sdocs_mfr_milestones x
                    join sdocs sd on sd.doc_id = x.doc_id
                where sd.doc_id in (select id from @docs)
                group by x.doc_id, sd.status_id

        exec tracer_log @tid, 'norm_labor_hours'
            insert into #result(
                mfr_doc_id, product_id, job_place_id, item_id, oper_id, q_brutto_product, norm_labor_hours
                )
            select 
                o.mfr_doc_id, c.product_id, o.place_id, c.item_id, o.oper_id,
                max(c.q_brutto_product),
                sum(c.q_brutto_product * do.duration_wk * dur.factor / dur_h.factor)
            from sdocs_mfr_opers o
                join sdocs_mfr_contents c on c.content_id = o.content_id
                    join sdocs_mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = o.number
                        join projects_durations dur on dur.duration_id = do.duration_wk_id
                        join projects_durations dur_h on dur_h.duration_id = 2
            where o.mfr_doc_id in (select id from @docs)
                and o.oper_id in (select oper_id from #result where oper_id is not null)
            group by o.mfr_doc_id, o.place_id, c.product_id, c.item_id, o.oper_id

        exec tracer_log @tid, 'bind item_status_id, oper_status_id'
            update x set item_status_id = c.status_id, oper_status_id = o.status_id
            from #result x
                join sdocs_mfr_opers o on o.oper_id = x.oper_id
                    join sdocs_mfr_contents c on c.content_id = o.content_id

        exec tracer_log @tid, 'bind oper_post_id'
            update x set 
                oper_post_id = e.post_id,
                oper_d_from_plan = o.d_from_plan
            from #result x
                join sdocs_mfr_opers o on o.oper_id = x.oper_id
                    join sdocs_mfr_contents c on c.content_id = o.content_id
                        join sdocs_mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = o.number
                            join sdocs_mfr_drafts_opers_executors e on e.draft_id = do.draft_id and e.oper_id = do.oper_id

        exec tracer_log @tid, 'bind limits'
            insert into #result(job_place_id, oper_post_id, labor_hours_limit, labor_persons_limit)
            select rs.place_id, rs.post_id, rs.quantity * rs.loading, rs.quantity
            from (
                select distinct job_place_id from #result
                ) x
                join mfr_places_posts rs on rs.place_id = x.job_place_id
    end

    else begin
        -- labor_hours
            insert into #result(
                job_place_id, mfr_doc_id, product_id, oper_post_id, norm_labor_hours, labor_hours
                )
            select 
                o.place_id, o.mfr_doc_id, c.product_id, e.post_id, 
                sum(c.q_brutto_product * do.duration_wk * dur.factor / dur_h.factor),
                sum(case when o.status_id = 100 then o.duration_wk * dur.factor / dur_h.factor end)
            from sdocs_mfr_opers o
                join sdocs_mfr_contents c on c.content_id = o.content_id
                    join sdocs_mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = o.number
                        join sdocs_mfr_drafts_opers_executors e on e.draft_id = do.draft_id and e.oper_id = do.oper_id and e.is_deleted = 0
                join projects_durations dur on dur.duration_id = o.duration_wk_id
                join projects_durations dur_h on dur_h.duration_id = 2
            where o.d_to_plan between @period_from and @period_to
            group by o.place_id, o.mfr_doc_id, c.product_id, e.post_id
            having sum(c.q_brutto_product * do.duration_wk * dur.factor / dur_h.factor) > 0.1;

        -- bind limits & deficits
            insert into #result(job_place_id, labor_hours_limit, labor_persons_limit, labor_persons_deficit)
            select 
                rs.place_id,
                rs.q_loading,
                rs.quantity,
                floor((nullif(rs.q_loading, 0) - x.sum_hours / @period_days) / 8.)
            from (
                select
                    job_place_id,
                    sum(norm_labor_hours) as sum_hours
                from #result group by job_place_id
                ) x
                join (
                    select
                        place_id, 
                        sum(case when quantity > 0 then loading end) as loading,
                        sum(quantity * loading) as q_loading,
                        sum(case when loading > 0 then quantity end) as quantity
                    from mfr_places_posts
                    group by place_id
                ) rs on rs.place_id = x.job_place_id

            update #result set labor_persons_deficit = null where labor_persons_deficit >= 0;
    end
	exec tracer_log @tid, 'final select'
		select
			PlanName = pln.number,
			DepartmentName = depts.name,
			PersonName = isnull(jp.person_name, '-'),
			JobPlaceName = isnull(pl.full_name, '-'),
			JobStatus = js.name,
			MfrNumber = sd.number,
			ProductName = p.name,
			JobNumber = isnull(j.number, ''),
			JobDateOpened = j.d_doc,
			JobDateClosed = cast(j.d_closed as date),
			ItemName = pi.name,
			ItemStatus = isnull(st1.name, '-'),
			ItemQuantity = jp.q_brutto_product,
			OperName = o.name,
			OperDateFrom = cast(o.d_from as date),
			OperDateTo = cast(o.d_to as date),
			OperDateFromPlan = jp.oper_d_from_plan,
			OperDateToPlan = cast(o.d_to_plan as date),
			OperMonth = dbo.date2month(o.d_to),
			OperStatus = isnull(st2.name, '-'),

			OperPost = isnull(nullif(mp.name, ''), '-'),
			LaborHoursDay = jp.labor_hours,
			NormLaborHours = jp.norm_labor_hours,
			LaborHours = jp.labor_hours,
			LaborHoursLimit = jp.labor_hours_limit,
			LaborPersonsLimit = jp.labor_persons_limit,
            LaborPersonsDeficit = jp.labor_persons_deficit,
			PlanJobHid = concat('#', jp.plan_job_id),
			PersonHid = concat('#', jp.person_id)
		from #result jp
			left join mols m on m.mol_id = jp.person_id
				left join depts on depts.dept_id = m.dept_id
			left join mols_posts mp on mp.post_id = jp.oper_post_id
			left join v_mfr_plans_jobs j on j.plan_job_id = jp.plan_job_id
			left join mfr_places pl on pl.place_id = jp.job_place_id
			left join products p on p.product_id = jp.product_id
			left join products pi on pi.product_id = jp.item_id
			left join sdocs sd on sd.doc_id = jp.mfr_doc_id
				left join mfr_plans pln on pln.plan_id = sd.plan_id
			left join sdocs_mfr_opers o on o.oper_id = jp.oper_id		
			left join mfr_jobs_statuses js on js.status_id = jp.job_status_id
			left join mfr_items_statuses st1 on st1.status_id = jp.item_status_id
			left join mfr_items_statuses st2 on st2.status_id = jp.oper_status_id

	final:
		exec drop_temp_table '#contents,#opers,#result'
		exec tracer_close @tid
end
GO
-- exec mfr_reps_jobs_persons 1000, @folder_id = -1, @context = 'docs'
-- exec mfr_reps_jobs_persons 1000, @period_from = '2025-03-01', @period_to = '2025-03-31'
