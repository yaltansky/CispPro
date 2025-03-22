if object_id('mfr_reps_jobs_persons_completed') is not null drop proc mfr_reps_jobs_persons_completed
go
create proc mfr_reps_jobs_persons_completed
	@mol_id int,	
	@d_from date = null,
	@d_to date = null,
	@folder_id int = null -- папка табелей
as
begin
    set nocount on;

    create table #ids(id int primary key);
    
    -- #ids
        if @folder_id is not null begin
            if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
            insert into #ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfw'
        end
        else
            insert into #ids select wk_sheet_id from mfr_wk_sheets where d_doc between @d_from and @d_to
                and status_id >= 0

    -- #wk_sheets
        create table #wk_sheets(
            wk_sheet_id int,
            wksheet_date datetime,
            place_id int,
            wk_shift varchar(50),
            person_id int,
            workers_count int,
            wk_hours float,
            completed_count int
            );

    -- wksheet
        insert into #wk_sheets(
            wk_sheet_id, wksheet_date, place_id, wk_shift,
            person_id, wk_hours, workers_count
            )
        select
            x.wk_sheet_id, w.d_doc, w.place_id, w.wk_shift,
            x.mol_id,
            coalesce(x.wk_hours, 0),
            (
                select sum(c_person) from (
                    select 1 as c_person from mfr_wk_sheets_details where wk_sheet_id = w.wk_sheet_id and id = x.id
                    union all
                    select 1 from mfr_wk_sheets_details where wk_sheet_id = w.wk_sheet_id and parent_id = x.id
                    ) c
            )
        from mfr_wk_sheets_details x
            join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
                join #ids i on i.id = w.wk_sheet_id
        where x.parent_id is null;

    -- #jobs
        create table #jobs(
            wk_sheet_id int,
            d_doc date,
            person_id int,
            job_id int,
            job_detail_id int,
            plan_q float,
            fact_q float,
            duration_days int,
            norm_hours float,
            norm_hours_daily float,
            plan_hours float,
            fact_hours float,
            fact_hours_sum float,
            completed bit not null default(0)
        );

        insert into #jobs(
            wk_sheet_id, d_doc, person_id, job_id, job_detail_id, 
            duration_days, norm_hours,
            plan_hours, fact_hours,
            plan_q, fact_q
            )
        select 
            je.wk_sheet_id, je.d_doc, je.mol_id, jd.plan_job_id, jd.id, 
            coalesce(ceiling(jd.norm_duration), 1),
            jd.norm_duration_wk * dur.factor / dur_h.factor,
            je.plan_duration_wk,
            je.duration_wk,
            coalesce(nullif(je.plan_q, 0), jd.plan_q), je.fact_q
        from mfr_plans_jobs_details jd
            join (
                select distinct wj.wk_sheet_id, wj.detail_id
                from mfr_wk_sheets_jobs wj
                    join #ids wi on wi.id = wj.wk_sheet_id
            ) wj on wj.detail_id = jd.id
            join mfr_plans_jobs_executors je on je.detail_id = jd.id and je.wk_sheet_id = wj.wk_sheet_id
            join projects_durations dur on dur.duration_id = jd.duration_wk_id
            join projects_durations dur_h on dur_h.duration_id = 2; -- hours

    update #jobs set norm_hours_daily = norm_hours / nullif(duration_days, 0);

    -- fact_hours_sum
        create table #jobs_days(
            id int identity primary key,
            job_detail_id int,
            d_doc date,
            fact_hours float,
            fact_hours_sum float,
            index ix__jobs_days(job_detail_id, d_doc)
            );
        
        insert into #jobs_days(job_detail_id, d_doc, fact_hours)
        select je.detail_id, je.d_doc, sum(duration_wk)
        from mfr_plans_jobs_executors je
        where je.detail_id in (select distinct job_detail_id from #jobs)
        group by je.detail_id, je.d_doc;

        update x set fact_hours_sum = xx.fact_hours_sum
        from #jobs_days x
            join (
                select id,
                    sum(fact_hours) over (partition by job_detail_id order by d_doc) as fact_hours_sum
                from #jobs_days
            ) xx on xx.id = x.id;

        update x set fact_hours_sum = xx.fact_hours_sum
        from #jobs x
            join #jobs_days xx on xx.job_detail_id = x.job_detail_id and xx.d_doc = x.d_doc

    -- Если длительность операции (Длительность) <= 1 день, то если Кф = Кп, то Ис = 1, иначе 0
        update #jobs set completed = 1 where plan_q = fact_q;

    -- Если длительность операции (Длительность) > 1 день,
        -- если Тф (на день Табеля) >= Тн (задания) / Длительность (и это если СуммаТф < Тн), то Ис = 1
        update #jobs set completed = 1 
        where duration_days > 1
            and fact_hours >= norm_hours_daily
            and fact_hours_sum < norm_hours
            and completed = 0;

    -- Если все строки СЗ с Индикатором = 1, то Индикатор СЗ = 1, иначе - 0.
        update x set completed_count = workers_count * case when count_jobs = count_completed_jobs then 1 else 0 end
        from #wk_sheets x
            join (
                select wk_sheet_id, person_id,
                    count(*) as count_jobs,
                    sum(case when completed = 1 then 1 end) as count_completed_jobs
                from #jobs
                group by wk_sheet_id, person_id
            ) cc on cc.wk_sheet_id = x.wk_sheet_id and cc.person_id = x.person_id;

    -- select * from #wk_sheets;
    -- select * from #jobs where person_id = 2970;

    -- #results
        create table #results(
            wk_sheet_id int,
            wksheet_date datetime,
            place_id int,
            wk_shift varchar(50),
            -- 
            person_id int,
            workers_count int,
            wk_hours float,
            completed_count int,
            -- 
            job_id int,
            job_detail_id int,
            job_plan_q float,
            job_fact_q float,
            job_duration_days int,
            job_norm_hours float,
            job_norm_hours_daily float,
            job_plan_hours float,
            job_fact_hours float,
            job_fact_hours_sum float,
            job_completed bit
            );

        insert into #results(wk_sheet_id, wksheet_date, place_id, wk_shift, person_id, workers_count, wk_hours, completed_count)
        select wk_sheet_id, wksheet_date, place_id, wk_shift, person_id, workers_count, wk_hours, completed_count
        from #wk_sheets;

        insert into #results(
            wk_sheet_id, wksheet_date, place_id, wk_shift, person_id,
            job_id, job_detail_id, job_plan_q, job_fact_q, job_duration_days, job_norm_hours, job_norm_hours_daily, job_plan_hours, job_fact_hours, job_fact_hours_sum, job_completed
            )
        select 
            w.wk_sheet_id, w.d_doc, w.place_id, w.wk_shift, j.person_id,
            job_id, job_detail_id, plan_q, fact_q, duration_days, norm_hours, norm_hours_daily, plan_hours, fact_hours, fact_hours_sum, completed
        from #jobs j
            join mfr_wk_sheets w on w.wk_sheet_id = j.wk_sheet_id

    select
        concat(pl.name, '-', pl.note) as WksheetPlaceName,
        x.wksheet_date as WksheetDate,
        x.wk_shift as WksheetShift,
        --
        mols.name as PersonName,
        x.workers_count as WorkersCount,
        x.wk_hours as WkHours,
        x.completed_count as WkCompletedCount,
        --
        p.name as JobItemName,
        jd.oper_name as JobOperName,
        x.job_duration_days as JobDurationDays,
        x.job_plan_q as JobPlanQ,
        x.job_fact_q as JobFactQ,
        x.job_norm_hours as JobNormHours,
        x.job_plan_hours as JobPlanHours,
        x.job_fact_hours as JobFactHours,
        x.job_fact_hours_sum as JobFactHoursSum,
        x.job_completed as JobCompleted,
        -- 
        concat('#', x.wk_sheet_id) as WksheetHid,
        concat('#', x.job_id) as JobHid
    from #results x
        join mfr_places pl on pl.place_id = x.place_id
        join mols on mols.mol_id = x.person_id
            join mols_posts mp on mp.post_id = mols.post_id
        left join mfr_plans_jobs_details jd on jd.id = x.job_detail_id
            left join products p on p.product_id = jd.item_id

    exec drop_temp_table '#ids,#wk_sheets,#jobs,#jobs_days,#results';
end
GO
-- exec mfr_reps_jobs_persons_completed 1000, @folder_id = -1;
