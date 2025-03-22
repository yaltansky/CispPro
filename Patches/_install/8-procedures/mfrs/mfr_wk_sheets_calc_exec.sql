if object_id('mfr_wk_sheets_calc_exec') is not null drop proc mfr_wk_sheets_calc_exec
go
create proc mfr_wk_sheets_calc_exec
    @d_from date = null,
    @d_to date = null,
    @folder_id int = null
as
begin
    -- #wsce_wk_sheets
        if @folder_id is not null begin
            create table #wsce_wk_sheets(id int primary key);
            insert into #wsce_wk_sheets exec objs_folders_ids @folder_id, 'mfw';
            select @d_from = w.d_from, @d_to = w.d_to
            from (
                select min(d_doc) as d_from, max(d_doc) as d_to
                from mfr_wk_sheets
                where wk_sheet_id in (select id from #wsce_wk_sheets)
                ) w;
            drop table #wsce_wk_sheets;
        end;

    create table #executors(
        exec_id int primary key,
        d_doc date,
        mol_id int,
        wk_shift varchar(30),
        place_id int,
        job_detail_id int,
        wk_sheet_id int,
        plan_hours float,
        fact_hours float,
        fact_q float
        );
        create index ix__executors1 on #executors(d_doc, mol_id);
        create index ix__executors2 on #executors(job_detail_id);

    insert into #executors(
        exec_id,
        place_id,
        d_doc, mol_id, wk_shift, job_detail_id,
        plan_hours, fact_hours, fact_q
        )
    select 
        e.id,
        j.place_id,
        e.d_doc, e.mol_id, coalesce(e.wk_shift, '1'), jd.id,
        e.plan_duration_wk, e.duration_wk, isnull(jd.fact_q, jd.plan_q)
    from mfr_plans_jobs_executors e
        join mfr_plans_jobs_details jd on jd.id = e.detail_id
            join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id and j.type_id = 1 and j.status_id >= 0
    where e.d_doc between @d_from and @d_to;

    -- Дата-Участок-Смена-Работник
    update f set wk_sheet_id = w.wk_sheet_id
    from #executors f
        join mfr_wk_sheets w on 
                w.place_id = f.place_id
            and w.d_doc = f.d_doc 
            and coalesce(w.wk_shift, '1') = f.wk_shift
        join mfr_wk_sheets_details wd on wd.wk_sheet_id = w.wk_sheet_id and wd.mol_id = f.mol_id
    where w.d_doc between @d_from and @d_to;

    -- Дата-Смена-Работник
    update f set wk_sheet_id = w.wk_sheet_id
    from #executors f
        join mfr_wk_sheets w on 
                w.d_doc = f.d_doc 
            and coalesce(w.wk_shift, '1') = f.wk_shift
        join mfr_wk_sheets_details wd on wd.wk_sheet_id = w.wk_sheet_id and wd.mol_id = f.mol_id
    where w.d_doc between @d_from and @d_to
        and f.wk_sheet_id is null;

    -- Дата-Смена-Работник
    update f set wk_sheet_id = w.wk_sheet_id
    from #executors f
        join mfr_wk_sheets w on w.d_doc = f.d_doc 
        join mfr_wk_sheets_details wd on wd.wk_sheet_id = w.wk_sheet_id and wd.mol_id = f.mol_id
    where w.d_doc between @d_from and @d_to
        and f.wk_sheet_id is null;

    update x set wk_sheet_id = e.wk_sheet_id
    from mfr_plans_jobs_executors x
        join #executors e on e.exec_id = x.id;

    drop table
        #executors;
end
go
