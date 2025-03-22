if object_id('mfr_wk_sheet_calc') is not null drop proc mfr_wk_sheet_calc
go
-- exec mfr_wk_sheet_calc 10872
create proc mfr_wk_sheet_calc
	@wk_sheet_id int,
	@trace bit = 0
as
begin
    declare 
        @d_doc date = (select d_doc from mfr_wk_sheets where wk_sheet_id = @wk_sheet_id),
        @place_id int = (select place_id from mfr_wk_sheets where wk_sheet_id = @wk_sheet_id),
        @where_rows varchar(100),
        @salaryVersion varchar(10) = isnull(dbo.app_registry_varchar('MfrWkSheetCalcSalary'), 'version2'),
        @wk_completion_koef float = isnull(cast(dbo.app_registry_value('MfrWkSheetCalcSalaryWkCompletion') as float), 1),
        @period_from date,
        @period_to date,
        @month_from date,
        @month_to date,
        @wk_days int,
        @tid int;

    -- prepare
        set nocount on;
        set transaction isolation level read uncommitted;

        declare @proc_name varchar(50) = object_name(@@procid)
        exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace;

        delete from mfr_wk_sheets_jobs where wk_sheet_id = @wk_sheet_id;
        update mfr_wk_sheets set wk_shift = nullif(wk_shift, '') where wk_sheet_id = @wk_sheet_id;

	exec tracer_log @tid, 'read jobs'
    	create table #wkcalc_jobs(
			exec_id int primary key,
			exec_status_id int,
			detail_id int,
			d_doc date
			);

		insert into #wkcalc_jobs(exec_id, exec_status_id, detail_id, d_doc)
		select j.exec_id, j.exec_status_id, j.detail_id, j.d_doc
		from (
			select distinct wk_sheet_id, mol_id from mfr_wk_sheets_details where wk_sheet_id = @wk_sheet_id
			) wd
			join mfr_wk_sheets w on w.wk_sheet_id = wd.wk_sheet_id
			join (
				select
					e.id as exec_id,
					case when e.duration_wk > 0 then 100 else j.status_id end as exec_status_id,
					e.detail_id,
					e.d_doc,
					e.mol_id,
					isnull(e.wk_shift, '1') as wk_shift
				from mfr_plans_jobs_executors e
					join mfr_plans_jobs_details jd on jd.id = e.detail_id
						join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
				where j.status_id >= 0
			) j on j.mol_id = wd.mol_id
		where wd.wk_sheet_id = @wk_sheet_id
			and isnull(w.wk_shift, j.wk_shift) = j.wk_shift
			and (j.d_doc = w.d_doc);

    exec tracer_log @tid, 'read norms (if required)'
		-- post_id, rate_price
		update x set post_id = oe.post_id, rate_price = oe.rate_price
		from mfr_plans_jobs_executors x
			join #wkcalc_jobs j on j.exec_id = x.id
			join mfr_plans_jobs_details jd with(nolock) on jd.id = x.detail_id					
				join sdocs_mfr_contents c with(nolock) on c.content_id = jd.content_id
				join mfr_drafts_opers o with(nolock) on o.draft_id = c.draft_id and o.number = jd.oper_number
					join mfr_drafts_opers_executors oe with(nolock) on oe.draft_id = c.draft_id and oe.oper_id = o.oper_id
		where isnull(x.rate_price,0) = 0

    exec tracer_log @tid, 'mfr_wk_sheets_jobs'
        
		insert into mfr_wk_sheets_jobs(
			wk_sheet_id, mol_id,
			plan_job_id, exec_status_id, salary_status_id, place_id, mfr_number, product_id, item_id,
			oper_date, oper_number, oper_name, oper_note, resource_id,
			id, detail_id, d_doc, norm_hours, plan_hours_day, fact_hours_day, rate_price,
			plan_q, fact_q, plan_day_q, fact_day_q, wk_shift,
			slice
			)
		select 
			w.wk_sheet_id, j.mol_id,
			j.plan_job_id, j.exec_status_id, j.salary_status_id, j.place_id, j.mfr_number, j.product_id, j.item_id,
			j.oper_date, j.oper_number, j.oper_name, j.oper_note, j.resource_id,
			j.id, j.detail_id, j.d_doc, j.norm_hours, j.plan_hours_day, j.fact_hours_day, j.rate_price,
			j.plan_q, j.fact_q, j.plan_day_q, j.fact_day_q, j.wk_shift,
			case when j.d_doc = w.d_doc then 'salary' else 'queue' end
		from mfr_wk_sheets w
			join (
				select
					j.plan_job_id,					
					jj.exec_status_id,
					case when cast(j.d_closed as date) = @d_doc then 100 else 0 end as "salary_status_id",
					jj.d_doc,
					e.mol_id,
					isnull(o.place_id, j.place_id) as "place_id",
					mfr.number as "mfr_number",
					jd.product_id,
					jd.item_id,
					isnull(o.d_from_plan, jj.d_doc) as "oper_date",
					jd.oper_number,
					jd.oper_name,
					isnull(e.wk_shift, '1') as "wk_shift",
					e.note as "oper_note",
					isnull(o.resource_id, jd.resource_id) as "resource_id",
					-- 
					e.id, e.detail_id,
					jd.plan_q,
					case when cast(j.d_closed as date) = @d_doc then jd.fact_q end as "fact_q",
					case when e.d_doc = @d_doc then e.plan_q end as "plan_day_q",
					case when e.d_doc = @d_doc then e.fact_q end as "fact_day_q",
					jd.norm_duration_wk * dur.factor / dur_h.factor as "norm_hours",
					e.plan_duration_wk * dur.factor / dur_h.factor as "plan_hours_day",
					e.duration_wk * dur.factor / dur_h.factor as "fact_hours_day",
					e.rate_price * jd.norm_duration_wk / nullif(jd.plan_q,0) as "rate_price" -- стоимость изготовления одной детали
				from mfr_plans_jobs_executors e
					join #wkcalc_jobs jj on jj.exec_id = e.id
					join mfr_plans_jobs_details jd on jd.id = e.detail_id
						join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
						left join sdocs_mfr_opers o on o.oper_id = jd.oper_id
						left join sdocs_mfr mfr on mfr.doc_id = jd.mfr_doc_id
                    join projects_durations dur on dur.duration_id = isnull(e.plan_duration_wk_id, e.duration_wk_id)
                    join projects_durations dur_h on dur_h.duration_id = 2 -- часы
			) j on 1 = 1
		where w.wk_sheet_id = @wk_sheet_id
            and j.mol_id is not null;

    exec tracer_log @tid, 'calc tree'
		update x set 
            name = mols.name, wk_post_id = mols.post_id
		from mfr_wk_sheets_details x
			join mols on mols.mol_id = x.mol_id
		where x.wk_sheet_id = @wk_sheet_id

		update x set
            parent_id = xx.id
		from mfr_wk_sheets_details x
			join mfr_wk_sheets_details xx on xx.wk_sheet_id = x.wk_sheet_id and xx.mol_id = x.parent_id
		where x.wk_sheet_id = @wk_sheet_id and x.note = 'imported'

		update mfr_wk_sheets_details set note = null
		where wk_sheet_id = @wk_sheet_id and note = 'imported'

		set @where_rows = concat('wk_sheet_id = ', @wk_sheet_id);
		exec tree_calc_nodes 'mfr_wk_sheets_details', 'id', @where_rows = @where_rows, @use_sort_id = 1;

    exec tracer_log @tid, 'calc plan_hours, fact_hours'

        -- #totals
            create table #totals(
                mol_id int, wk_shift varchar(20), salary float,
                primary key (mol_id, wk_shift)
                );

        -- #salary
            create table #salary(
                wk_detail_id int, d_doc date,
                parent_mol_id int, wk_shift varchar(20), mol_id int, post_id int, ktu float, k_inc float, wk_hours float,
                ratio float,
                plan_hours float, fact_hours float,
                plan_salary float, fact_salary float
                );
                create index ix__salary on #salary(parent_mol_id);

        update mfr_wk_sheets_details
        set plan_hours = null, fact_hours = null, queue_hours = null
        where wk_sheet_id = @wk_sheet_id;

        create table #wk_hours(mol_id int primary key, plan_hours float, fact_hours float, queue_hours float)
            insert into #wk_hours(mol_id, plan_hours, fact_hours, queue_hours)
            select
                wj.mol_id,
                sum(case when wj.d_doc = w.d_doc then wj.plan_hours_day end),
                sum(case when wj.d_doc = w.d_doc then wj.fact_hours_day end),
                sum(case when wj.exec_status_id != 100 then wj.plan_hours_day end)
            from mfr_wk_sheets_jobs wj
                join mfr_wk_sheets w on w.wk_sheet_id = wj.wk_sheet_id
            where wj.wk_sheet_id = @wk_sheet_id
            group by wj.mol_id;
        
        insert into mfr_wk_sheets_details(wk_sheet_id, mol_id, wk_hours, wk_ktu, note)
        select @wk_sheet_id, mol_id, 8, 1, 'добавлено автоматически'
        from #wk_hours h
        where not exists(
            select 1 from mfr_wk_sheets_details
            where wk_sheet_id = @wk_sheet_id
                and parent_id is null
                and mol_id = h.mol_id
            );

        update x set
            plan_hours = h.plan_hours,
            fact_hours = h.fact_hours
        from mfr_wk_sheets_details x
            join #wk_hours h on h.mol_id = x.mol_id and x.parent_id is null
        where x.wk_sheet_id = @wk_sheet_id;

    exec tracer_log @tid, 'calc metrix'
        exec mfr_wk_sheet_calc;2 @wk_sheet_id;

    exec tracer_log @tid, 'calc salary'

        -- @wks_period
            set @period_from = dbo.week_start(@d_doc);
            set @period_to = @d_doc;

            declare @wks_period app_pkids
                insert into @wks_period 
                select wk_sheet_id from mfr_wk_sheets 
                where d_doc between @period_from and @period_to
                    and status_id >= 0

		if @salaryVersion = 'version1' begin
            -- clear
                update mfr_wk_sheets_details set 
                    wk_ktu = isnull(wk_ktu,1),
                    wk_k_inc = isnull(wk_k_inc,1) 
                where wk_sheet_id = @wk_sheet_id;

                delete from mfr_wk_sheets_salary where wk_sheet_id = @wk_sheet_id;

            -- plan_salary, fact_salary (jobs)
                update x set
                    plan_salary = x.plan_day_q * x.rate_price,
                    fact_salary = x.fact_day_q * x.rate_price
                from mfr_wk_sheets_jobs x
                where x.wk_sheet_id = @wk_sheet_id

                exec mfr_wk_sheet_calc;3 @wk_sheet_id; -- distribute plan_hours, fact_hours (для бригады)

            -- salary
                -- save
                    insert into mfr_wk_sheets_salary(
                        wk_sheet_id, wk_detail_id, d_doc, parent_mol_id, mol_id,
                        post_id, wk_hours, wk_shift, ktu, k_inc,
                        salary_base, salary,
                        period_from, period_to
                        )
                    select
                        @wk_sheet_id, s.wk_detail_id, s.d_doc, s.parent_mol_id, s.mol_id,
                        s.post_id, s.wk_hours, j.wk_shift, s.ktu, s.k_inc,
                        s.ratio * j.salary,
                        s.ratio * j.salary * s.k_inc,
                        @period_from, @period_to
                    from #salary s
                        join #totals j on j.mol_id = s.parent_mol_id

                -- salary_period
                    update x set 
                        salary_period = wd.salary
                    from mfr_wk_sheets_salary x
                        join (
                            select mol_id, 
                                salary = sum(salary)
                            from mfr_wk_sheets_salary s
                                join mfr_wk_sheets w on w.wk_sheet_id = s.wk_sheet_id
                            where s.wk_sheet_id in (select id from @wks_period)
                            group by mol_id
                        ) wd on wd.mol_id = x.mol_id
                    where wk_sheet_id = @wk_sheet_id
        end;

        else if @salaryVersion = 'version2' begin
            
            -- clear
                update mfr_wk_sheets_details set 
                    wk_ktu = isnull(wk_ktu,1),
                    wk_k_inc = isnull(wk_k_inc,1),
                    wk_ktd = isnull(wk_ktd, 0)
                where wk_sheet_id = @wk_sheet_id;

                delete from mfr_wk_sheets_salary where wk_sheet_id = @wk_sheet_id;
            
            exec mfr_wk_sheet_calc;3 @wk_sheet_id; -- distribute plan_hours, fact_hours (для бригады)

            -- salary_scale
                set @month_from = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc);
                set @month_to = dateadd(d, -1, dateadd(m, 1, @month_from));
                set @wk_days = (select count(*) from calendar c where day_date between @month_from and @month_to and type = 0);

                -- by sale_price (по окладу)
                update x set 
                    salary_scale = e.sale_price / nullif(@wk_days, 0) / 8 * x.wk_hours
                from mfr_wk_sheets_details x
                    join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                where wk_sheet_id = @wk_sheet_id
                    and e.sale_price > 0

                -- by rate_price (по тарифу)
                update x set 
                    salary_scale = e.rate_price * j.norm_hours
                from mfr_wk_sheets_details x
                    join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                    join (
                        select wk_sheet_id, mol_id, sum(norm_hours) as norm_hours
                        from mfr_wk_sheets_jobs
                        where fact_q >= plan_q -- только по сделанным деталям
                        group by wk_sheet_id, mol_id
                    ) j on j.wk_sheet_id = x.wk_sheet_id and j.mol_id = x.mol_id
                where x.wk_sheet_id = @wk_sheet_id
                    and e.rate_price > 0
            
                -- wk_completion от бригадира
                update x set
                    wk_completion = xp.wk_completion
                from mfr_wk_sheets_details x
                    join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
                    join mfr_wk_sheets_details xp on xp.wk_sheet_id = x.wk_sheet_id and xp.id = x.parent_id
                where x.wk_sheet_id = @wk_sheet_id

                -- by rate_price от бригадира
                update x set 
                    salary_scale = e.rate_price 
                        * j.norm_hours -- нормативное время по заданиям бригадира
                        * x.wk_hours / (xp.wk_hours + nullif(dp.wk_hours, 0)), -- доля табельного времени сотрудника в бригаде
                    wk_completion = isnull(x.wk_completion, 1) -- сдельщикам начисляют только за время
                from mfr_wk_sheets_details x
                    join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                    join mfr_wk_sheets_details xp on xp.wk_sheet_id = x.wk_sheet_id and xp.id = x.parent_id
                        join (
                            select wk_sheet_id, mol_id, sum(norm_hours) as norm_hours
                            from mfr_wk_sheets_jobs
                            where fact_q >= plan_q -- только по сделанным деталям
                            group by wk_sheet_id, mol_id
                        ) j on j.wk_sheet_id = x.wk_sheet_id and j.mol_id = xp.mol_id
                    join (
                        select wk_sheet_id, parent_id, wk_hours = sum(wk_hours)
                        from mfr_wk_sheets_details
                        group by wk_sheet_id, parent_id
                    ) dp on dp.wk_sheet_id = x.wk_sheet_id and xp.id = dp.parent_id
                where x.wk_sheet_id = @wk_sheet_id
                    and e.rate_price > 0

            -- save
                insert into mfr_wk_sheets_salary(
                    wk_sheet_id, wk_detail_id, parent_mol_id, mol_id,
                    wk_shift, post_id, wk_hours, ktu, k_inc, ktd, wk_completion,
                    salary_base, salary_award,
                    period_from, period_to
                    )
                select
                    @wk_sheet_id, x.id, xp.mol_id, x.mol_id,
                    w.wk_shift, x.wk_post_id, x.wk_hours, x.wk_ktu, x.wk_k_inc, x.wk_ktd, x.wk_completion,
                    x.salary_scale * x.wk_k_inc,
                    (x.salary_scale * x.wk_k_inc) * isnull(x.wk_completion, 1) * (1 - x.wk_ktd) * @wk_completion_koef,
                    @period_from, @period_to
                from mfr_wk_sheets_details x
                    join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
                    left join mfr_wk_sheets_details xp on xp.wk_sheet_id = x.wk_sheet_id and xp.id = x.parent_id
                where x.wk_sheet_id = @wk_sheet_id

                -- wk_hours_period, ktd_period, wk_completion_period
                    update x set 
                        wk_hours_period = xsum.wk_hours,
                        ktd_period = case when xsum.wk_ktd >= 0.5 then 0.5 else xsum.wk_ktd end,
                        wk_completion_period = xsum.wk_completion_wavg
                    from mfr_wk_sheets_salary x
                        join (
                            select mol_id, 
                                wk_hours = sum(wk_hours),
                                wk_ktd = sum(wk_ktd),
                                wk_completion_wavg = sum(wk_completion * wk_hours) / nullif(sum(wk_hours), 0)
                            from mfr_wk_sheets_details
                            where wk_sheet_id in (select id from @wks_period)
                            group by mol_id
                        ) xsum on xsum.mol_id = x.mol_id
                    where wk_sheet_id = @wk_sheet_id

                -- salary_base_period, salary_award_period
                    update x set 
                        salary_base_period = wd.salary_base,
                        salary_award_period = wd.salary_base * x.wk_completion_period * (1 - x.ktd_period) * @wk_completion_koef
                    from mfr_wk_sheets_salary x
                        join (
                            select mol_id, 
                                salary_base = sum(salary_base)
                            from mfr_wk_sheets_salary s
                                join mfr_wk_sheets w on w.wk_sheet_id = s.wk_sheet_id
                            where s.wk_sheet_id in (select id from @wks_period)
                            group by mol_id
                        ) wd on wd.mol_id = x.mol_id
                    where wk_sheet_id = @wk_sheet_id

                -- salary, salary_period
                    update mfr_wk_sheets_salary set 
                        salary = salary_base + isnull(salary_award,0),
                        salary_period = salary_base_period + isnull(salary_award_period,0)
                    where wk_sheet_id = @wk_sheet_id;
        end
        
        else if @salaryVersion = 'version3' begin
            
            -- clear
                update mfr_wk_sheets_details set 
                    wk_ktu = isnull(wk_ktu,1),
                    wk_k_inc = isnull(wk_k_inc,1),
                    wk_ktd = isnull(wk_ktd, 0)
                where wk_sheet_id = @wk_sheet_id;

                delete from mfr_wk_sheets_salary where wk_sheet_id = @wk_sheet_id;
            
            exec mfr_wk_sheet_calc;3 @wk_sheet_id; -- distribute plan_hours, fact_hours (для бригады)

            -- @wk_days
                set @month_from = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc);
                set @month_to = dateadd(d, -1, dateadd(m, 1, @month_from));
                set @wk_days = (select count(*) from calendar c where day_date between @month_from and @month_to and type = 0);
            
            -- Тн(р), Тф(р), К(р) ...
                -- tables
                    create table #wk_mols(id int primary key);

                    create table #salary_opers(
                        job_detail_id int primary key,
                        salary_status_id int,
                        norm_hours float, -- Тн(о): Нормативное время по каждой операции 
                        fact_hours float, -- Тф(о): фактическое время работников
                        );
                    
                    create table #salary_opers_mols(
                        job_detail_id int,
                        mol_id int,
                        d_doc date,
                        salary_status_id int,
                        plan_hours float,       -- Тп(о,р)
                        fact_hours float,       -- Тф(о,р)
                        fact_hours_sum float,   -- Тф(о) = Сумма(Тф(о,р))
                        norm_hours float,       -- Тн(о,р) = Тн(о) * Тф(о,р) / Тф(о): Нормативное время работника на исполнение операции
                        plan_q float,
                        fact_q float,
                        primary key(job_detail_id, mol_id, d_doc)
                        );

                -- opers (полнота заданий)
                    insert into #wk_mols select distinct mol_id from mfr_wk_sheets_details where wk_sheet_id = @wk_sheet_id

                    insert into #salary_opers(job_detail_id, salary_status_id)
                    select 
                        jd.id,
                        case when cast(j.d_closed as date) = @d_doc then 100 else 0 end
                    from mfr_plans_jobs_details jd
                        join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
                    where (
                            -- либо по участку
                            j.place_id = @place_id
                            -- либо по списку сотрудников табеля (бардак в учёте, однако ...)
                            or exists(
                                select 1 from mfr_plans_jobs_executors where detail_id = jd.id and mol_id in (select id from #wk_mols)
                                )
                        )
                        and (
                            (j.status_id between 0 and 99)
                            or (j.status_id = 100 and cast(j.d_closed as date) >= @d_doc)
                        )
                        and exists(
                            select 1 from mfr_plans_jobs_executors where d_doc <= @d_doc and detail_id = jd.id
                        );

                    -- norm_hours, fact_hours (of oper)
                        update x set
                            norm_hours = coalesce(xx.norm_hours, xx.fact_hours),
                            fact_hours = xx.fact_hours
                        from #salary_opers x
                            join (
                                select e.detail_id, 
                                    max(jd.norm_duration_wk * dur.factor / dur_h.factor) as norm_hours,
                                    sum(e.duration_wk * dur.factor / dur_h.factor) as fact_hours
                                from mfr_plans_jobs_executors e
                                    join #salary_opers op on op.job_detail_id = e.detail_id
                                    join mfr_plans_jobs_details jd on jd.id = e.detail_id
                                    join projects_durations dur on dur.duration_id = isnull(e.plan_duration_wk_id, e.duration_wk_id)
                                    join projects_durations dur_h on dur_h.duration_id = 2 -- часы
                                where e.d_doc <= @d_doc
                                group by e.detail_id
                            ) xx on xx.detail_id = x.job_detail_id;

                -- opers + mols
                    insert into #salary_opers_mols(
                        job_detail_id, mol_id, d_doc, plan_hours, fact_hours, plan_q, fact_q
                        )
                    select 
                        wj.detail_id,
                        coalesce(wdc.mol_id, wd.mol_id), 
                        w.d_doc,
                        sum(wj.plan_hours_day * coalesce(wdc.wk_ratio, 1)),
                        sum(wj.fact_hours_day * coalesce(wdc.wk_ratio, 1)),
                        sum(wj.plan_day_q),
                        sum(wj.fact_day_q)
                    from mfr_wk_sheets_jobs wj
                        join #salary_opers o on o.job_detail_id = wj.detail_id
                        join mfr_wk_sheets w on w.wk_sheet_id = wj.wk_sheet_id
                        join mfr_wk_sheets_details wd on wd.wk_sheet_id = wj.wk_sheet_id and wd.mol_id = wj.mol_id
                            left join mfr_wk_sheets_details wdc on wdc.wk_sheet_id = wd.wk_sheet_id and wdc.parent_id = wd.id
                    where w.d_doc <= @d_doc
                    group by 
                        wj.detail_id,
                        coalesce(wdc.mol_id, wd.mol_id), 
                        w.d_doc;

                    -- salary_status_id
                        update x set
                            salary_status_id = o.salary_status_id
                        from #salary_opers_mols x
                            join #salary_opers o on o.job_detail_id = x.job_detail_id;

                    -- fact_hours_sum
                        update x set
                            fact_hours_sum = xx.fact_hours
                        from #salary_opers_mols x
                            join (
                                select job_detail_id, sum(fact_hours) as "fact_hours"
                                from #salary_opers_mols
                                group by job_detail_id
                            ) xx on xx.job_detail_id = x.job_detail_id;

                    -- norm_hours (by mols)
                        update sm set
                            norm_hours = so.norm_hours * sm.fact_hours / nullif(sm.fact_hours_sum, 0)
                        from #salary_opers_mols sm
                            join #salary_opers so on so.job_detail_id = sm.job_detail_id;

                -- DEBUG
                    -- create table #salary_mols(
                    --     mol_id int,
                    --     salary_status_id int,
                    --     norm_hours float,   -- Тн(р) = Сумма(Тн(о,р)): Нормативное время работника по завершенным операциям
                    --     fact_hours float,   -- Тф(р) = Сумма(Тф(о,р)): Фактическое время работника по завершенным операциям
                    --     efficiency float,   -- Эфф(р) = Тн(р) / Тф(р): Производительность показывает ускорение работ по сравнению с нормативным
                    --     k_efficiency float,   -- К(р) = Если(Эфф(р) < 1.2 То Эфф(р), Иначе 1.2)
                    --     award float, -- ИПР = ОкладЧас(р) * Тф(р) * 
                    --     primary key(mol_id, salary_status_id)
                    --     );
                    -- 
                    -- -- Производительность работника по завершенным операциям:
                    --     insert into #salary_mols(mol_id, salary_status_id, norm_hours, fact_hours, efficiency)
                    --     select 
                    --         mol_id, 
                    --         salary_status_id,
                    --         sum(norm_hours), sum(fact_hours),
                    --         sum(norm_hours) / nullif(sum(fact_hours), 0)
                    --     from #salary_opers_mols
                    --     group by mol_id, salary_status_id;

                    --     update #salary_mols set 
                    --         k_efficiency = case when efficiency > 1.2 then 1.2 else efficiency end;

                    -- -- ИПР (индивидуальная премия работника)
                    --     -- по окладу
                    --     update x set
                    --         award = e.sale_price / nullif(@wk_days, 0) / 8 * x.fact_hours * x.k_efficiency
                    --     from #salary_mols x
                    --         join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                    --     where e.sale_price > 0;

                    --     -- по почасовой ставка
                    --     update x set
                    --         award = e.rate_price * x.fact_hours * x.efficiency
                    --     from #salary_mols x
                    --         join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                    --     where e.rate_price > 0;

                -- mfr_wk_sheets_jobs (full)
                    delete from mfr_wk_sheets_jobs where wk_sheet_id = @wk_sheet_id;

                    insert into mfr_wk_sheets_jobs(
                        wk_sheet_id,
                        plan_job_id, place_id, mfr_number, product_id, item_id, 
                        oper_date, oper_number, oper_name,
                        id, -- exec_id
                        detail_id, mol_id, d_doc, wk_shift, 
                        exec_status_id, 
                        salary_status_id, 
                        post_id,
                        plan_q,
                        fact_q,
                        plan_day_q,
                        fact_day_q,
                        norm_hours,
                        fact_hours,
                        plan_hours_day,
                        fact_hours_day,
                        norm_hours_mol,
                        fact_hours_mol,
                        slice 
                        )
                    select 
                        wd.wk_sheet_id,
                        j.plan_job_id, j.place_id, mfr.number, jd.product_id, jd.item_id,
                        isnull(o.d_to_plan, @d_doc), jd.oper_number, jd.oper_name,
                        0,
                        x.job_detail_id, wd.mol_id, w.d_doc, w.wk_shift, 
                        x.salary_status_id, -- exec_status_id, 
                        x.salary_status_id, 
                        wd.wk_post_id,
                        cast(max(jd.plan_q) as decimal(18,2)), -- plan_q
                        cast(max(case when cast(j.d_closed as date) = @d_doc then jd.fact_q end) as decimal(18,2)), -- fact_q
                        cast(sum(case when x.d_doc = @d_doc then je.plan_q end) as decimal(18,2)), -- plan_day_q
                        cast(sum(case when x.d_doc = @d_doc then je.fact_q end) as decimal(18,2)), -- fact_day_q
                        max(jd.norm_duration_wk), -- Тн(о), norm_hours
                        max(je_all.fact_hours), -- Тф(о, <тб), fact_hours
                        cast(sum(case when x.d_doc = @d_doc then je.plan_hours end) as decimal(18,2)), -- Тп(о,р,тб), plan_hours_day
                        cast(sum(case when x.d_doc = @d_doc then je.fact_hours end) as decimal(18,2)), -- Тф(о,р,тб), fact_hours_day
                        cast(sum(x.norm_hours) as decimal(18,2)), -- Тн(о,р,<тб)
                        cast(sum(x.fact_hours) as decimal(18,2)), -- Тф(о,р,<тб)
                        'full'
                    from #salary_opers_mols x
                        join mfr_plans_jobs_details jd on jd.id = x.job_detail_id
                            join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
                            join sdocs_mfr mfr on mfr.doc_id = jd.mfr_doc_id
                            left join sdocs_mfr_opers o on o.oper_id = jd.oper_id
                        join (
                            select 
                                job_detail_id, mol_id, d_doc,
                                sum(plan_hours) as plan_hours,
                                sum(fact_hours) as fact_hours,
                                sum(plan_q) as plan_q,
                                sum(fact_q) as fact_q
                            from #salary_opers_mols
                            group by job_detail_id, mol_id, d_doc
                        ) je on je.job_detail_id = x.job_detail_id and je.mol_id = x.mol_id and je.d_doc = x.d_doc
                        join (
                            select 
                                job_detail_id,
                                sum(fact_hours) as fact_hours
                            from #salary_opers_mols
                            group by job_detail_id
                        ) je_all on je_all.job_detail_id = x.job_detail_id
                        join mfr_wk_sheets_details wd on wd.wk_sheet_id = @wk_sheet_id and wd.mol_id = x.mol_id
                            join mfr_wk_sheets w on w.wk_sheet_id = wd.wk_sheet_id
                    group by 
                        wd.wk_sheet_id,
                        j.plan_job_id, j.place_id, mfr.number, jd.product_id, jd.item_id,
                        o.d_to_plan, jd.oper_number, jd.oper_name,
                        x.job_detail_id, wd.mol_id, w.d_doc, w.wk_shift, 
                        x.salary_status_id, 
                        wd.wk_post_id;

            -- salary_scale, salary_price, wk_completion
                -- by sale_price (по окладу)
                update x set 
                    salary_scale = e.sale_price / nullif(@wk_days, 0) / 8 * x.wk_hours,
                    salary_price = e.sale_price / nullif(@wk_days, 0) / 8
                from mfr_wk_sheets_details x
                    join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                where wk_sheet_id = @wk_sheet_id
                    and e.sale_price > 0;

                -- by rate_price (по тарифу)
                update x set 
                    salary_scale = e.rate_price * j.norm_hours,
                    salary_price = e.rate_price
                from mfr_wk_sheets_details x
                    join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                    join (
                        select wk_sheet_id, mol_id, sum(norm_hours) as norm_hours
                        from mfr_wk_sheets_jobs
                        where fact_q >= plan_q -- только по сделанным деталям
                        group by wk_sheet_id, mol_id
                    ) j on j.wk_sheet_id = x.wk_sheet_id and j.mol_id = x.mol_id
                where x.wk_sheet_id = @wk_sheet_id
                    and e.rate_price > 0;
            
                -- wk_completion от бригадира
                update x set
                    wk_completion = xp.wk_completion
                from mfr_wk_sheets_details x
                    join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
                    join mfr_wk_sheets_details xp on xp.wk_sheet_id = x.wk_sheet_id and xp.id = x.parent_id
                where x.wk_sheet_id = @wk_sheet_id;

                -- by rate_price от бригадира
                update x set 
                    salary_scale = e.rate_price 
                        * j.norm_hours -- нормативное время по заданиям бригадира
                        * x.wk_hours / (xp.wk_hours + nullif(dp.wk_hours, 0)), -- доля табельного времени сотрудника в бригаде
                    wk_completion = isnull(x.wk_completion, 1) -- сдельщикам начисляют только за время
                from mfr_wk_sheets_details x
                    join mols_employees e on e.mol_id = x.mol_id and e.date_fire is null
                    join mfr_wk_sheets_details xp on xp.wk_sheet_id = x.wk_sheet_id and xp.id = x.parent_id
                        join (
                            select wk_sheet_id, mol_id, sum(norm_hours) as norm_hours
                            from mfr_wk_sheets_jobs
                            where fact_q >= plan_q -- только по сделанным деталям
                            group by wk_sheet_id, mol_id
                        ) j on j.wk_sheet_id = x.wk_sheet_id and j.mol_id = xp.mol_id
                    join (
                        select wk_sheet_id, parent_id, wk_hours = sum(wk_hours)
                        from mfr_wk_sheets_details
                        group by wk_sheet_id, parent_id
                    ) dp on dp.wk_sheet_id = x.wk_sheet_id and xp.id = dp.parent_id
                where x.wk_sheet_id = @wk_sheet_id
                    and e.rate_price > 0;

            -- mfr_wk_sheets_salary
                insert into mfr_wk_sheets_salary(
                    wk_sheet_id, wk_detail_id, parent_mol_id, mol_id,
                    wk_shift, post_id, wk_hours, ktu, k_inc, ktd, wk_completion,
                    salary_base,
                    period_from, period_to
                    )
                select
                    @wk_sheet_id, x.id, xp.mol_id, x.mol_id,
                    w.wk_shift, x.wk_post_id, x.wk_hours, x.wk_ktu, x.wk_k_inc, x.wk_ktd, x.wk_completion,
                    
                    -- salary_base
                    x.salary_scale * x.wk_k_inc,

                    @period_from, @period_to
                from mfr_wk_sheets_details x
                    join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
                    left join mfr_wk_sheets_details xp on xp.wk_sheet_id = x.wk_sheet_id and xp.id = x.parent_id
                where x.wk_sheet_id = @wk_sheet_id;

                -- norm_hours, fact_hours, wk_completion
                    update x set 
                        norm_hours = xx.norm_hours,
                        fact_hours = xx.fact_hours,
                        wk_completion = xx.norm_hours / nullif(xx.fact_hours, 0)
                    from mfr_wk_sheets_salary x
                        join (
                            select mol_id, sum(norm_hours) as norm_hours, sum(fact_hours) as fact_hours
                            from #salary_opers_mols
                            where salary_status_id = 100
                            group by mol_id
                        ) xx on xx.mol_id = x.mol_id
                    where x.wk_sheet_id = @wk_sheet_id;

                -- norm_hours_period, fact_hours_period, wk_completion_period
                    update x set 
                        norm_hours_period = xx.norm_hours,
                        fact_hours_period = xx.fact_hours,
                        wk_completion_period = xx.norm_hours / nullif(xx.fact_hours, 0)
                    from mfr_wk_sheets_salary x
                        join (
                            select mol_id, 
                                sum(norm_hours) as norm_hours,
                                sum(fact_hours) as fact_hours
                            from mfr_wk_sheets_salary s
                            where s.wk_sheet_id in (select id from @wks_period)
                            group by mol_id
                        ) xx on xx.mol_id = x.mol_id
                    where wk_sheet_id = @wk_sheet_id;

                -- wk_hours_period, ktd_period, wk_completion_period
                    update x set 
                        wk_hours_period = xsum.wk_hours,
                        ktd_period = case when xsum.wk_ktd >= 0.5 then 0.5 else xsum.wk_ktd end
                    from mfr_wk_sheets_salary x
                        join (
                            select mol_id, 
                                sum(wk_hours) as wk_hours,
                                sum(wk_ktd) as wk_ktd
                            from mfr_wk_sheets_details
                            where wk_sheet_id in (select id from @wks_period)
                            group by mol_id
                        ) xsum on xsum.mol_id = x.mol_id
                    where wk_sheet_id = @wk_sheet_id;

                -- salary_award
                    update x set 
                        salary_award = wd.salary_price * x.fact_hours * xx.wk_completion
                    from mfr_wk_sheets_salary x
                        join (
                            select id, 
                                case when wk_completion > 1.2 then 1.2 else wk_completion end as wk_completion
                             from mfr_wk_sheets_salary
                        ) xx on xx.id = x.id
                        join mfr_wk_sheets_details wd on wd.wk_sheet_id = x.wk_sheet_id and wd.id = x.wk_detail_id
                    where x.wk_sheet_id = @wk_sheet_id;
                    
                -- salary_base_period, salary_award_period
                    update x set 
                        salary_base_period = wd.salary_base,
                        salary_award_period = wd.salary_award
                    from mfr_wk_sheets_salary x
                        join (
                            select mol_id, 
                                sum(salary_base) as salary_base,
                                sum(salary_award) as salary_award
                            from mfr_wk_sheets_salary s
                                join mfr_wk_sheets w on w.wk_sheet_id = s.wk_sheet_id
                            where s.wk_sheet_id in (select id from @wks_period)
                            group by mol_id
                        ) wd on wd.mol_id = x.mol_id
                    where wk_sheet_id = @wk_sheet_id;

                -- salary, salary_period
                    update mfr_wk_sheets_salary set 
                        salary = salary_base + isnull(salary_award,0),
                        salary_period = salary_base_period + isnull(salary_award_period,0)
                    where wk_sheet_id = @wk_sheet_id;           
        end;

    exec tracer_log @tid, 'misc';
        update x set 
            has_childs = wd.has_childs,
            level_id = wd.level_id,
            sort_id = wd.sort_id
        from mfr_wk_sheets_salary x
            join mfr_wk_sheets_details wd on wd.id = x.wk_detail_id
        where x.wk_sheet_id = @wk_sheet_id;

	exec tracer_close @tid;
    
    exec drop_temp_table '#wkcalc_jobs,#totals,#salary,#wk_hours,#salary_opers,#salary_opers_mols,#salary_mols,#wk_sheets';
end
go
-- helper: calc metrix
create proc mfr_wk_sheet_calc;2
    @wk_sheet_id int = null,
    @wk_sheets app_pkids readonly
as
begin
    create table #wk_sheets(id int primary key, d_doc date)
        insert into #wk_sheets(id, d_doc)
        select wk_sheet_id, d_doc from mfr_wk_sheets
        where (@wk_sheet_id is null or wk_sheet_id = @wk_sheet_id)
            and (not exists(select 1 from @wk_sheets) or wk_sheet_id in (select id from @wk_sheets))

    -- brig_executors, brig_wk_hours
        update x set 
            brig_executors = xx.c_execs + 1, 
            brig_wk_hours = x.wk_hours + xx.wk_hours
        from mfr_wk_sheets_details x
            join (
                select wk_sheet_id, parent_id, c_execs = count(*), wk_hours = sum(wk_hours)
                from mfr_wk_sheets_details
                where wk_hours > 0
                group by wk_sheet_id, parent_id
            ) xx on xx.wk_sheet_id = x.wk_sheet_id and xx.parent_id = x.id
        where x.wk_sheet_id in (select id from #wk_sheets)
            and x.parent_id is null

    -- wk_exec_rows, wk_exec_rows_completed
        update x set 
            wk_exec_rows = xx.c_rows, 
            wk_exec_rows_completed = isnull(xx.c_rows_completed, 0)
        from mfr_wk_sheets_details x
            join (
                select wk_sheet_id, mol_id,
                    c_rows = count(distinct j.detail_id),
                    c_rows_completed = sum(case when j.fact_q >= j.plan_q then 1 end)
                from mfr_wk_sheets_jobs j
                group by wk_sheet_id, mol_id
            ) xx on xx.wk_sheet_id = x.wk_sheet_id and xx.mol_id = x.mol_id
        where x.wk_sheet_id in (select id from #wk_sheets)

    -- wk_completion

        -- -- by quantity
        --     update x set wk_completion = nullif(
        --         case
        --             when j.fact_day_q > j.plan_day_q then 1
        --             when j.fact_day_q <= j.plan_day_q then j.fact_day_q / nullif(j.plan_day_q,0)
        --             else 0
        --         end, 0)
        --     from mfr_wk_sheets_details x
        --         left join (
        --             select wk_sheet_id, mol_id,
        --                 plan_day_q = isnull(sum(plan_day_q), 0),
        --                 fact_day_q = isnull(sum(fact_day_q), 0)
        --             from mfr_wk_sheets_jobs
        --             group by wk_sheet_id, mol_id
        --         ) j on j.wk_sheet_id = x.wk_sheet_id and j.mol_id = x.mol_id
        --     where x.wk_sheet_id = @wk_sheet_id
        --         and x.parent_id is null

        -- by normal intensity
            -- % исполнение сменного задания = Sum ( (Тф/Тт) * (1/Кн) ), где
            --  Тф - фактическое время на операцию
            --  Тт - табельное время
            --  Кн - превышение нормативной трудоёмкости операции = Тф / Тн = { Тф/Тн, если >1; 1, если <=1 }
            --      для завершённых операций Кн = 1
        update x set 
            wk_completion = 
                case 
                    when j.wk_completion = 1 and x.wk_exec_rows_completed = 0 then 0.99
                    when j.wk_completion > 1 then 1 
                    else j.wk_completion 
                end
        from mfr_wk_sheets_details x
            join (
                select j.wk_sheet_id, j.mol_id,
                    wk_completion = sum( 
                        j.fact_hours_day / nullif(isnull(jw.brig_wk_hours, jw.wk_hours),0) 
                        * case 
                            when j.salary_status_id = 0 then (1 / nullif(jsum.k_norm, 0)) -- по не завершённым вычисляем перерасход нормативного времени
                            else 1 -- по завершённым заданиям =1
                            end
                        )
                from mfr_wk_sheets_jobs j
                    join mfr_wk_sheets_details jw on jw.wk_sheet_id = j.wk_sheet_id and jw.mol_id = j.mol_id
                    join (
                        select 
                            wi.id as wk_sheet_id,
                            e.detail_id,
                            case 
                                when sum(e.duration_wk) > max(wj.norm_hours) 
                                    then sum(e.duration_wk) / nullif(max(wj.norm_hours),0) 
                                else 1 
                            end as k_norm
                        from mfr_plans_jobs_executors e
                            join mfr_wk_sheets_jobs wj on wj.detail_id = e.detail_id
                            cross apply #wk_sheets wi
                        where e.d_doc <= wi.d_doc
                            and wj.wk_sheet_id = wi.id
                        group by wi.id, e.detail_id
                    ) jsum on jsum.wk_sheet_id = jw.wk_sheet_id and jsum.detail_id = j.detail_id
                group by j.wk_sheet_id, j.mol_id
            ) j on j.wk_sheet_id = x.wk_sheet_id and j.mol_id = x.mol_id
            join #wk_sheets wi on wi.id = x.wk_sheet_id
        where x.parent_id is null
            and x.wk_hours > 0

    exec drop_temp_table '#wk_sheets'
end
go
-- helper: calc plan_hours, fact_hours (бригада)
create proc mfr_wk_sheet_calc;3
    @wk_sheet_id int
as
begin
    declare
        @salaryVersion varchar(max) = isnull(dbo.app_registry_varchar('MfrWkSheetCalcSalary'), 'version2');

    -- #totals
        insert into #totals(mol_id, wk_shift, salary)
        select mol_id, wk_shift, sum(fact_salary)
        from mfr_wk_sheets_jobs
        where wk_sheet_id = @wk_sheet_id
        group by mol_id, wk_shift;
        
    -- #salary
        insert into #salary(
            wk_detail_id, d_doc, parent_mol_id, mol_id, post_id, ktu, k_inc, wk_hours,
            plan_hours, fact_hours
            )
        select 
            wd.id, w.d_doc, isnull(wdp.mol_id, wd.mol_id),
            wd.mol_id, wd.wk_post_id, wd.wk_ktu, wd.wk_k_inc, wd.wk_hours,
            isnull(wdp.plan_hours, wd.plan_hours), isnull(wdp.fact_hours, wd.fact_hours)
        from mfr_wk_sheets_details wd
            join mfr_wk_sheets w on w.wk_sheet_id = wd.wk_sheet_id
            left join mfr_wk_sheets_details wdp on wdp.wk_sheet_id = wd.wk_sheet_id and wdp.id = wd.parent_id
        where wd.wk_sheet_id = @wk_sheet_id;

    -- ratio
        update x set
            ratio = (x.ktu * x.wk_hours / nullif(xx.wk_hours,0))
        from #salary x
            join (
                select parent_mol_id, sum(ktu * wk_hours) as "wk_hours"
                from #salary
                group by parent_mol_id
            ) xx on xx.parent_mol_id = x.parent_mol_id;

    -- save plah_hours, fact_hours
    if @salaryVersion = 'version3' begin
        update x set 
            wk_ratio = s.ratio,
            plan_hours = s.plan_hours * s.ratio, 
            fact_hours = s.fact_hours * s.ratio
        from mfr_wk_sheets_details x
            join #salary s on s.wk_detail_id = x.id
        where x.wk_sheet_id = @wk_sheet_id;
    end;
end
go
