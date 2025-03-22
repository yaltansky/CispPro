if object_id('mfr_opers_wiz') is not null drop proc mfr_opers_wiz
go
-- exec mfr_opers_wiz 1000, 503, null, 23401, 'wkSheetDetails'
create proc mfr_opers_wiz
	@mol_id int,
    @place_id int,
    @part varchar(50),
    @equipment_id int = null,
    @wk_sheet_id int = null
as
begin
    set nocount on;

    declare @today date = dbo.today()
    declare @d_doc date

    -- #executors
    create table #executors(
        ROW_ID INT IDENTITY PRIMARY KEY,
        MOL_ID INT,
        HAS_CHILDS BIT,
        NAME VARCHAR(250),
        POST_NAME VARCHAR(250),
        WK_SHEET_ID INT,
        WK_HOURS FLOAT,
        LEFT_HOURS FLOAT
        )

    -- info
        if @part = 'equipments'
        begin
            set @d_doc = (select d_doc from mfr_wk_sheets where wk_sheet_id = @wk_sheet_id)

            SELECT E.RESOURCE_ID, E.NAME, PE.LOADING, LEFT_LOADING = PE.LOADING - ISNULL(J.LOADING_DAY, 0)
            from mfr_resources e
                join mfr_places_equipments pe on pe.place_id = @place_id and pe.resource_id = e.resource_id
                join (
                    select distinct o.resource_id
                    from mfr_sdocs_opers o
                        join mfr_sdocs mfr on mfr.doc_id = o.mfr_doc_id and mfr.plan_status_id = 1 and mfr.status_id between 0 and 99
                    where o.place_id = @place_id
                        and o.status_id != 100 -- не сделано
                        and o.resource_id is not null
                ) oo on oo.resource_id = e.resource_id
                -- existing jobs
                left join (
                    select dr.resource_id, loading_day = sum(c.q_brutto_product * dr.loading)
                    from mfr_plans_jobs_details jd with(nolock)
                        join mfr_plans_jobs j with(nolock) on j.plan_job_id = jd.plan_job_id and j.status_id >= 0
                        join sdocs_mfr_opers o with(nolock) on o.oper_id = jd.oper_id
                            join sdocs_mfr_contents c with(nolock) on c.content_id = o.content_id
                                join mfr_drafts_opers do with(nolock) on do.draft_id = c.draft_id and do.number = o.number
                                    join mfr_drafts_opers_resources dr with(nolock) on dr.draft_id = do.draft_id and dr.oper_id = do.oper_id
                    where o.place_id = @place_id
                        and jd.id in (select detail_id from mfr_plans_jobs_executors with(nolock) where d_doc = @d_doc)
                    group by dr.resource_id
                ) j on j.resource_id = e.resource_id
            order by e.name
        end

        if @part = 'workers'
            insert into #executors(
                mol_id, name, post_name, left_hours, wk_sheet_id
                )
            select x.mol_id, mols.name, post_name = mp.name, left_hours = x.fact_hours, wd.wk_sheet_id
            from (
                select top 20 je.mol_id, 
                    fact_hours = sum(je.duration_wk * dur.factor / dur_h.factor)
                from mfr_plans_jobs_details jd with(nolock)
                    join mfr_plans_jobs_executors je with(nolock) on je.detail_id = jd.id
                        join projects_durations dur on dur.duration_id = je.duration_wk_id
                        join projects_durations dur_h on dur_h.duration_id = 2
                where je.d_doc between dateadd(m, -3, @today) and @today
                    and resource_id = @equipment_id
                group by je.mol_id
                having sum(je.duration_wk * dur.factor / dur_h.factor) > 1
                ) x
                join mols on mols.mol_id = x.mol_id
                    join mols_posts mp on mp.post_id = mols.post_id
                left join mfr_wk_sheets_details wd with(nolock) on wd.wk_sheet_id = @wk_sheet_id and wd.mol_id = x.mol_id
            order by x.fact_hours desc

        if @part = 'wkSheetDetails' 
        begin
            set @d_doc = (select d_doc from mfr_wk_sheets where wk_sheet_id = @wk_sheet_id)

            create table #assigns(mol_id int PRIMARY KEY, plan_hours float)
                insert into #assigns(mol_id, plan_hours)
                select mol_id, plan_hours = sum(e.plan_duration_wk * dur.factor / dur_h.factor)
                from mfr_plans_jobs_executors e
                    join projects_durations dur on dur.duration_id = e.duration_wk_id
                    join projects_durations dur_h on dur_h.duration_id = 2
                where d_doc = @d_doc
                group by mol_id

            insert into #executors(
                mol_id, name, post_name, has_childs, wk_hours, left_hours
                )
            select 
                mol_id, name, post_name, x.has_childs, wk_hours,
                left_hours = wk_hours - isnull(plan_hours, 0)
            from (
                select wd.mol_id, wd.name, post_name = mp.name, wd.has_childs,
                    wk_hours = isnull(wd.brig_wk_hours, wd.wk_hours),
                    e.plan_hours, wd.sort_id
                from mfr_wk_sheets_details wd with(nolock) 
                    join mols_posts mp on mp.post_id = wd.wk_post_id
                    left join #assigns e on e.mol_id = wd.mol_id
                where wk_sheet_id = @wk_sheet_id
                    and wd.parent_id is null
                ) x
            where wk_hours > 0
            order by sort_id, name
        end

    select * from #executors

    exec drop_temp_table '#executors,#assigns'
end
go
