if object_id('mfr_reps_wk_persons') is not null drop proc mfr_reps_wk_persons
go
-- exec mfr_reps_wk_persons 1000, @d_from = '2025-01-01', @d_to = '2025-01-31'
create proc mfr_reps_wk_persons
	@mol_id int,	
	@d_from date = null,
	@d_to date = null,
	@folder_id int = null, -- папка табелей
    @trace bit = 0
as
begin
    set nocount on;

    create table #wk_sheets(id int primary key);
    
    -- #wk_sheets
        if @folder_id is not null begin
            if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
            insert into #wk_sheets exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfw'
        end
        else
            insert into #wk_sheets select wk_sheet_id from mfr_wk_sheets where d_doc between @d_from and @d_to
                and status_id >= 0

    -- #results
        create table #results(
            wk_sheet_id int,
            wksheet_place_id int,
            wksheet_date datetime,
            -- 
            brigadier_name varchar(100),
            person_id int,
            person_name varchar(100),
            post_name varchar(150),
            wk_hours float,
            wk_ktu float,
            wk_k_inc float,
            -- 
            job_place_id int,
            job_status_id int,
            plan_job_id int index ix_job_id,
            mfr_doc_id int,
            item_id int,
            oper_id int index ix_oper,
            q_brutto_product float,		
            plan_hours float,
            fact_hours float
            );

    -- wksheet
        insert into #results(
            wk_sheet_id, wksheet_place_id, wksheet_date, -- wksheet
            brigadier_name, person_id, person_name, post_name,
            wk_hours, wk_ktu, wk_k_inc
            )
        select
            x.wk_sheet_id, w.place_id, w.d_doc,
            isnull(m2.name, mols.name), mols.mol_id, mols.name, mp.name,
            isnull(x.wk_hours, 0), x.wk_ktu, x.wk_k_inc
        from mfr_wk_sheets_details x
            left join mfr_wk_sheets_details xp on xp.wk_sheet_id = x.wk_sheet_id and xp.id = x.parent_id
                left join mols m2 on m2.mol_id = xp.mol_id
            join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
                join #wk_sheets i on i.id = w.wk_sheet_id
            join mols on mols.mol_id = x.mol_id
            left join mols_posts mp on mp.post_id = x.wk_post_id

    -- wksheet_fact_hours, fact_hours, queue_fact_hours
        -- sync mfr_plans_jobs_executors.wk_sheet_id
        exec mfr_wk_sheets_calc_exec @d_from, @d_to, @folder_id;

        create table #executors(
            d_doc date,
            mol_id int,
            wk_shift varchar(30),
            job_detail_id int,
            wk_sheet_id int,
            plan_hours float,
            fact_hours float,
            fact_q float
            );

        if @folder_id is null begin
            insert into #executors(
                d_doc, mol_id, wk_shift, wk_sheet_id, job_detail_id,
                plan_hours, fact_hours, fact_q
                )
            select 
                e.d_doc, e.mol_id, coalesce(e.wk_shift, '1'), e.wk_sheet_id, jd.id,
                e.plan_duration_wk, e.duration_wk, isnull(jd.fact_q, jd.plan_q)
            from mfr_plans_jobs_executors e
                join mfr_plans_jobs_details jd on jd.id = e.detail_id
                    join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id and j.type_id = 1 and j.status_id >= 0
                join mfr_wk_sheets w on w.wk_sheet_id = e.wk_sheet_id and w.d_doc = e.d_doc
            where e.d_doc between @d_from and @d_to;
        end

        else begin
            insert into #executors(
                d_doc, mol_id, wk_shift, wk_sheet_id, job_detail_id,
                plan_hours, fact_hours, fact_q
                )
            select 
                e.d_doc, e.mol_id, coalesce(e.wk_shift, '1'), e.wk_sheet_id, jd.id,
                e.plan_duration_wk, e.duration_wk, isnull(jd.fact_q, jd.plan_q)
            from mfr_plans_jobs_executors e
                join mfr_plans_jobs_details jd on jd.id = e.detail_id
                    join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id and j.type_id = 1 and j.status_id >= 0
                join mfr_wk_sheets w on w.wk_sheet_id = e.wk_sheet_id and w.d_doc = e.d_doc
            where e.wk_sheet_id in (select id from #wk_sheets);
        end;

        insert into #results(
            wk_sheet_id, wksheet_place_id, wksheet_date,
            brigadier_name, person_id, person_name, post_name, -- person
            job_place_id, job_status_id, plan_job_id, mfr_doc_id, item_id, oper_id, q_brutto_product, -- job
            plan_hours,
            fact_hours
            )
        select
            x.wk_sheet_id, w.place_id, x.d_doc, 
            ww.brigadier_name, mols.mol_id, mols.name, ww.post_name,
            j.place_id, j.status_id, j.plan_job_id, x.mfr_doc_id, x.item_id, x.oper_id,
            x.fact_q,
            x.plan_hours_day,
            x.fact_hours_day
        from (
            select 
                e.d_doc, e.mol_id, e.wk_sheet_id, jd.plan_job_id, jd.mfr_doc_id, jd.item_id, jd.oper_id,
                sum(e.plan_hours) as plan_hours_day,
                sum(e.fact_hours) as fact_hours_day,
                sum(e.fact_q) as fact_q
            from #executors e
                join mfr_plans_jobs_details jd on jd.id = e.job_detail_id
            group by
                e.d_doc, e.mol_id, e.wk_sheet_id, jd.plan_job_id, jd.mfr_doc_id, jd.item_id, jd.oper_id
            ) x
            join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
            join mfr_plans_jobs j on j.plan_job_id = x.plan_job_id
            join mols on mols.mol_id = x.mol_id		
            left join (
                select wk_sheet_id, person_id,
                    max(brigadier_name) as brigadier_name,
                    max(post_name) as post_name
                from #results
                group by wk_sheet_id, person_id
            ) ww on ww.wk_sheet_id = x.wk_sheet_id and ww.person_id = x.mol_id

    -- select
        select 
            WksheetDate = jp.wksheet_date,
            WksheetPlaceName = isnull(pl1.full_name, '-'),
            -- 
            DepartmentName = depts.name,
            BrigadierName = isnull(jp.brigadier_name, '-'),
            PersonName = isnull(jp.person_name, '-'),
            PersonPostName = jp.post_name,
            PersonWkHours = jp.wk_hours,
            PersonKTU = jp.wk_ktu,
            PersonK_INC = jp.wk_k_inc,
            -- 
            JobPlaceName = isnull(pl2.full_name, '-'),
            JobStatus = js.name,
            MfrNumber = sd.number,
            JobNumber = isnull(j.number, ''),
            JobDateOpened = j.d_doc,
            JobDateClosed = cast(j.d_closed as date),
            ItemName = p.name,
            ItemQuantity = jp.q_brutto_product,
            OperName = o.name,
            LaborPlanHours = jp.plan_hours,
            LaborFactHours = jp.fact_hours,
            LaborWorked = case when jp.wk_hours > 0 then 1 else 0 end,
            LaborNoWorked = case when jp.wk_hours = 0 then 1 else 0 end,
            -- 
            WksheetHid = concat('#', jp.wk_sheet_id),
            PlanJobHid = concat('#', jp.plan_job_id),
            PersonHid = concat('#', jp.person_id)
        from #results jp
            left join mols m on m.mol_id = jp.person_id
                left join depts on depts.dept_id = m.dept_id
            left join v_mfr_plans_jobs j on j.plan_job_id = jp.plan_job_id
            left join mfr_places pl1 on pl1.place_id = jp.wksheet_place_id
            left join mfr_places pl2 on pl2.place_id = jp.job_place_id
            left join products p on p.product_id = jp.item_id
            left join mfr_sdocs sd on sd.doc_id = jp.mfr_doc_id
            left join sdocs_mfr_opers o on o.oper_id = jp.oper_id		
            left join mfr_jobs_statuses js on js.status_id = jp.job_status_id

    exec drop_temp_table '#wk_sheets,#results';
end
GO

-- exec mfr_reps_wk_persons 1000, @d_from = '2024-12-01', @d_to = '2024-12-31'
-- exec mfr_reps_wk_persons 1000, @folder_id = -1
