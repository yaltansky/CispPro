if object_id('mfr_reps_jobs') is not null drop proc mfr_reps_jobs
go
-- exec mfr_reps_jobs 1000, @folder_id = 98, @d_doc = '2021-08-17'
-- exec mfr_reps_jobs 1000, @wk_sheet_id = 16212
create proc mfr_reps_jobs
	@mol_id int,	
	@d_doc datetime = null,
	@plan_id int = null,
	@folder_id int = null, -- папка сменных заданий
	@wk_sheet_id int = null
as
begin

	set nocount on;
	set transaction isolation level read uncommitted;

	-- #jobs
		create table #jobs(id int primary key)
		create table #jobs_details(id int primary key)
		declare @filter_jobs_details bit = 0

		if @d_doc is not null
			insert into #jobs 
			select plan_job_id from mfr_plans_jobs
			where type_id not in (2,3,4)
				and status_id >= 0
				and d_doc <= @d_doc
				and dbo.getday(isnull(d_closed, @d_doc)) >= @d_doc

		else if @wk_sheet_id is not null
		begin
			insert into #jobs_details
			select distinct j.detail_id
			from mfr_wk_sheets_jobs j
				join mfr_wk_sheets w on w.wk_sheet_id = j.wk_sheet_id
			where j.wk_sheet_id = @wk_sheet_id
				and j.d_doc = w.d_doc

			set @filter_jobs_details = 1

			insert into #jobs
			select distinct plan_job_id 
			from mfr_plans_jobs_details 
			where id in (select id from #jobs_details)
		end

		else
		begin
			if @folder_id is not null set @plan_id = null

			if @plan_id is not null insert into #jobs select plan_job_id from mfr_plans_jobs where plan_id = @plan_id and is_deleted = 0
			else insert into #jobs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfj'
		end

	-- #result
		select
			x.plan_job_id,
			x.status_id,
			x.item_id,
			x.mfr_number,
			x.mfr_priority,
			item_size = cast(null as varchar(200)),
			duration = cast(x.duration as int),
			plan_q = cast(null as int),
			fact_q = cast(null as int),
			reject_q = cast(null as int),
			plan_items_q = x.plan_q,
			fact_items_q = case when x.status_id = 100 then x.fact_q end,
			reject_items_q = case when x.status_id = -2 then x.plan_q end,
			x.problem_name,
			x.problem_note,
			oper_name = cast(null as varchar(250)),
			executor_name = cast(null as varchar(80)),
			executor_wk_norm_h = x.norm_duration_wk,
			executor_wk_plan_h = cast(null as float),
			executor_wk_fact_h = cast(null as float),
			executor_fact_q = cast(null as float),
			cast('items' as varchar(20)) as slice
		into #result
		from (
			select 
                place_id, plan_job_id, status_id, mfr_number, mfr_priority, item_id, problem_name, problem_note, 
                duration = sum(duration),
                norm_duration_wk = sum(norm_duration_wk),
                plan_q = max(plan_q), -- находим максимум по детали (поскольку нужно кол-во деталей, а не детале-операций)
                fact_q = max(fact_q) -- находим максимум по детали (поскольку нужно кол-во деталей, а не детале-операций)
            from (
                select 
                    j.place_id,
                    j.plan_job_id,
                    jj.status_id,
                    mfr_number = sd.number,
                    mfr_priority = min(sd.priority_id),
                    jd.item_id,
                    jd.oper_number,
                    problem_name = pbm.name,
                    problem_note = jd.note,
                    duration = sum(jd.norm_duration * dur.factor),
                    plan_q = sum(jd.plan_q), -- суммируем по операциям
                    fact_q = sum(jd.fact_q), -- суммируем по операциям
                    norm_duration_wk = sum(jd.norm_duration_wk)
                from mfr_plans_jobs_details jd
                    join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
                        join (
                            select 
                                plan_job_id,
                                status_id = case when cast(d_closed as date) > @d_doc then 2 else status_id end
                            from mfr_plans_jobs
                        ) jj on jj.plan_job_id = j.plan_job_id
                    join sdocs sd on sd.doc_id = jd.mfr_doc_id
                    join projects_durations dur on dur.duration_id = 3
                    left join mfr_plans_jobs_problems_types pbm on pbm.problem_id = jd.problem_id
                where (@filter_jobs_details = 0 or jd.id in (select id from #jobs_details))
                group by 
                    j.place_id, j.plan_job_id, jj.status_id, jd.item_id, sd.number, jd.oper_number,
                    pbm.name, jd.note
                ) xx
                group by place_id, plan_job_id, status_id, mfr_number, mfr_priority, item_id, problem_name, problem_note
			) x
		where x.plan_job_id in (select id from #jobs)

			create index ix_result1 on #result(plan_job_id)
			create index ix_result2 on #result(plan_job_id, item_id)

	-- totals
		insert into #result(
			plan_job_id, item_id, mfr_number, mfr_priority, duration, problem_name, problem_note, plan_q, fact_q, reject_q, slice
			)
		select
			plan_job_id, item_id, '',
			min(mfr_priority),
			duration, problem_name, problem_note,
			1, res_fact_q, res_reject_q,
			'totals'
		from (
			select *,
				res_fact_q = case when status_id = 100 then 1 end,
				res_reject_q = case when status_id = -2 then 1 end
			from #result
			) t
		group by 
			plan_job_id, item_id, duration, problem_name, problem_note, res_fact_q, res_reject_q

	-- problem_name, problem_note
		update x
		set problem_name = pbm.name,
			problem_note = xx.note
		from #result x
			join (
				select plan_job_id, item_id, problem_id, note
				from mfr_plans_jobs_details
				where problem_id is not null
			) xx on xx.plan_job_id = x.plan_job_id and xx.item_id = x.item_id
			left join mfr_plans_jobs_problems_types pbm on pbm.problem_id = xx.problem_id
		where x.problem_name is null

	-- executor_wk_plan_h, executor_wk_fact_h
		insert into #result(
			plan_job_id, item_id, mfr_number, mfr_priority, problem_name, problem_note, duration,
			oper_name, executor_name, executor_wk_plan_h, executor_wk_fact_h, executor_fact_q
			)
		select 
			jd.plan_job_id, jd.item_id, sd.number, r.mfr_priority, r.problem_name, r.problem_note, r.duration,
			jd.oper_name, mols.name,
			isnull(je.plan_duration_wk, je.duration_wk),
			je.duration_wk,
			je.fact_q
		from mfr_plans_jobs_details jd
			left join mfr_plans_jobs_executors je on je.detail_id = jd.id
				left join mols on mols.mol_id = je.mol_id
			join #result r on r.plan_job_id = jd.plan_job_id and r.item_id = jd.item_id and r.slice = 'totals'
			join sdocs sd on sd.doc_id = jd.mfr_doc_id
		where (@wk_sheet_id is null
			or (
				jd.id in (select id from #jobs_details)
				and exists(
						select 1
						from mfr_wk_sheets_details wd
							join mfr_wk_sheets w on w.wk_sheet_id = wd.wk_sheet_id
						where w.wk_sheet_id = @wk_sheet_id
							and w.d_doc = je.d_doc
							and wd.mol_id = je.mol_id
					)
				)
			)

	-- item_size 
		update x set item_size = left(sz.item_size,200)
		from #result x
			join (
				select jd.plan_job_id, jd.item_id, item_size = max(dr.prop_size)
				from mfr_plans_jobs_details jd
					join mfr_sdocs_contents c on c.content_id = jd.content_id
						join mfr_drafts dr on dr.draft_id = c.draft_id
				group by jd.plan_job_id, jd.item_id
			) sz on sz.plan_job_id = x.plan_job_id and sz.item_id = x.item_id

	declare @attr1_id int = (select top 1 attr_id from prodmeta_attrs where code = 'материал.Марка')
	declare @attr2_id int = (select top 1 attr_id from prodmeta_attrs where code = 'материал.Наименование')
	declare @attr3_id int = (select top 1 attr_id from prodmeta_attrs where code = 'материал.ПодгруппаНаименование')
	declare @attr4_id int = (select top 1 attr_id from prodmeta_attrs where code = 'материал.Примечание')

	update #result set oper_name = '' where oper_name is null

	-- final
		select x.*,
			 job_number = j.number,
			 place_name = isnull(pl.full_name, '-'),
			 jc_number = concat('MFJ.', x.plan_job_id, '.', x.item_id),
			 item_name = p.name,
			 item_material_name = concat(pa1.attr_value, case when pa2.attr_value is not null then ', ' end, pa2.attr_value),
			 item_material_group_name = pa3.attr_value,
			 item_material_note = pa4.attr_value,
			 item_date = cast(ji.d_from as date),
			 status_name = s.name,
			 j.d_doc,
			 d_closed = cast(j.d_closed as date),
			 duration_group = case when x.duration <= 1 then 'Однодневные' else 'Многодневные' end,
			 plan_job_hid = concat('#', x.plan_job_id)
		from #result x
			join mfr_plans_jobs j on j.plan_job_id = x.plan_job_id
				join mfr_jobs_statuses s on s.status_id = j.status_id
				left join mfr_places pl on pl.place_id = j.place_id
			left join (
				select plan_job_id = r.job_id, r.item_id, d_from = min(r.oper_date)
				from mfr_r_plans_jobs_items r
				group by r.job_id, r.item_id
			) ji on ji.plan_job_id = x.plan_job_id and ji.item_id = x.item_id
			join products p on p.product_id = x.item_id
			left join products_attrs pa1 on pa1.product_id = x.item_id and pa1.attr_id = @attr1_id
			left join products_attrs pa2 on pa2.product_id = x.item_id and pa2.attr_id = @attr2_id
			left join products_attrs pa3 on pa3.product_id = x.item_id and pa3.attr_id = @attr3_id
			left join products_attrs pa4 on pa4.product_id = x.item_id and pa4.attr_id = @attr4_id

	final:
		exec drop_temp_table '#jobs,#jobs_details,#result'
end
GO
