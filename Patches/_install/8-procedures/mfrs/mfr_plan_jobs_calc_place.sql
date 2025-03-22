if object_id('mfr_plan_jobs_calc_place') is not null drop proc mfr_plan_jobs_calc_place
go
-- exec mfr_plan_jobs_calc_place 502, 1
create proc mfr_plan_jobs_calc_place
    @place_id int,
    @enforce bit = 0
as
begin
	set nocount on;

	declare @today date = dbo.today()
    declare @d_calc datetime = isnull((select top 1 d_calc from mfr_r_plans_jobs_items_facts where place_id = @place_id), '1900-01-01')
	if @enforce = 0 and datediff(minute, @d_calc, getdate()) < 120
	begin
		print 'Register mfr_r_plans_jobs_items_facts is actual. No calculation nedeed.'
		return
	end

	-- #ms_contents
		create table #ms_contents(
			mfr_doc_id int,
			content_id int,
			place_id int,
            d_plan date,
			plan_q float,
			oper_id int index ix_oper,
			primary key (content_id, place_id)
			)
		insert into #ms_contents(mfr_doc_id, content_id, place_id, oper_id, d_plan,  plan_q)
        select r.mfr_doc_id, r.content_id, o.place_id, max(o.oper_id),
            max(o.d_to_plan),
			sum(r.plan_q)
		from mfr_r_plans_jobs_items r
            join sdocs_mfr_opers o on o.oper_id = r.oper_id
            join (
                select content_id, place_id, max_oper_id = max(oper_id)
                from sdocs_mfr_opers
                group by content_id, place_id
            ) mx on mx.max_oper_id = r.oper_id
		where o.place_id = @place_id
            and r.slice != '100%'
		group by r.mfr_doc_id, r.content_id, o.place_id
        having sum(r.plan_q) > 0

	-- select count(*) from #ms_contents
	-- -- -- select * from sdocs_mfr_opers where oper_id = 4682565
	-- return

	-- #ms_contents_fact
		create table #ms_contents_fact(
			row_id int identity primary key,
			mfr_doc_id int,
			content_id int,
            place_id int,
            oper_id int,
			d_fact date,
			fact_q float,
			fact_rq float,
			index ix1 (mfr_doc_id, content_id, place_id),
			index ix2 (content_id, d_fact)
			)

		-- детали
		insert into #ms_contents_fact(mfr_doc_id, content_id, place_id, oper_id, d_fact, fact_q)
		select 
            r.mfr_doc_id, r.content_id, c.place_id, r.oper_id,
			r.job_date,
			isnull(case when r.job_status_id = 100 then r.fact_q end, 0)
		from mfr_r_plans_jobs_items r
			join #ms_contents c on c.oper_id = r.oper_id
		where r.job_date is not null
		order by r.mfr_doc_id, r.content_id, c.place_id, r.job_date

        -- select * from #ms_contents_fact where content_id = 11158670
        -- return

	-- #ms_dates
		create table #ms_dates(
			mfr_doc_id int,
			content_id int,
			d_doc date,
			primary key (mfr_doc_id, content_id, d_doc)
			)
		insert into #ms_dates(mfr_doc_id, content_id, d_doc)
		select distinct mfr_doc_id, content_id, d_fact
		from #ms_contents_fact

		-- append #ms_dates
		insert into #ms_contents_fact(mfr_doc_id, content_id, place_id, d_fact, fact_q)
		select o.mfr_doc_id, o.content_id, o.place_id, d.d_doc, 0
		from #ms_contents o
			join #ms_dates d on d.mfr_doc_id = o.mfr_doc_id and d.content_id = o.content_id
		where not exists(
			select 1 from #ms_contents_fact 
			where content_id = o.content_id 
				and place_id = o.place_id 
				and d_fact = d.d_doc
			)

		insert into #ms_contents_fact(mfr_doc_id, content_id, place_id, d_fact, fact_q)
		select o.mfr_doc_id, o.content_id, o.place_id, @today, 0
		from #ms_contents o
		where not exists(select 1 from #ms_contents_fact where content_id = o.content_id)

	-- fact_rq
		update x set fact_rq = rq
		from #ms_contents_fact x
			join (
				select
					row_id,
					rq = sum(fact_q) over (partition by content_id, place_id order by d_fact)
				from #ms_contents_fact
			) xx on xx.row_id = x.row_id

	-- select * from #ms_contents_fact where place_id = 30 order by content_id, d_fact
	-- return

	-- #ms_items
		create table #ms_items(
			row_id int identity primary key,
			mfr_doc_id int,
			content_id int,
			place_id int,
			d_fact date,
			fact_rq float,
			round_rq float,
			diff_rq float,
			index ix (mfr_doc_id, content_id, d_fact)
			)

		insert into #ms_items(mfr_doc_id, content_id, place_id, d_fact, fact_rq, round_rq)
		select mfr_doc_id, content_id, place_id, d_fact, min(fact_rq), min(cast(fact_rq as int))
		from #ms_contents_fact
		group by mfr_doc_id, content_id, place_id, d_fact

		-- diff_rq
			update x set diff_rq = round_rq - isnull(prev_rq,0)
			from #ms_items x
				join (
					select
						row_id,
						prev_rq = lag(round_rq, 1, null) over (partition by mfr_doc_id, content_id order by d_fact)
					from #ms_items
				) xx on xx.row_id = x.row_id

	-- select * from #ms_items where place_id = 30
	-- return

	-- plan + fact (FIFO)
		-- #ms_plan
			create table #ms_plan(
				plan_row_id int identity primary key,
				mfr_doc_id int,
				content_id int,
				place_id int,
				d_plan date,
				value float,
				index ix_join (mfr_doc_id, content_id, place_id)
				)
			
			insert into #ms_plan(mfr_doc_id, content_id, place_id, d_plan, value)
			select mfr_doc_id, content_id, place_id, d_plan, plan_q
			from #ms_contents
			order by mfr_doc_id, content_id, place_id

	-- select * from #ms_plan where place_id = 30
	-- 	-- and mfr_doc_id = 1390988 order by plan_row_id
	-- return

		-- #ms_fact
			 create table #ms_fact(
				fact_row_id int identity primary key,
				mfr_doc_id int,
				content_id int,
				place_id int,
				d_fact date,
				value float,
				index ix (mfr_doc_id, content_id, place_id)
				)

			insert into #ms_fact(mfr_doc_id, content_id, place_id, d_fact, value)
			select mfr_doc_id, content_id, place_id, d_fact, diff_rq
			from #ms_items
			where diff_rq > 0
			order by mfr_doc_id, content_id, place_id, d_fact

	-- select * from #ms_fact where content_id = 11158670
	-- return

		-- FIFO
			create table #ms_fifo(
				row_id int identity primary key,
				fact_row_id int index ix_f,
				plan_row_id int index ix_p,
				mfr_doc_id int,
				content_id int,
				place_id int,
				d_plan date,
				d_fact date,
				plan_q float,
				fact_q float
				)
			
			declare @fid uniqueidentifier set @fid = newid()

			insert into #ms_fifo(
				plan_row_id, fact_row_id,
				mfr_doc_id, content_id, place_id, d_plan, d_fact,
				plan_q, fact_q
				)
			select
				r.plan_row_id, p.fact_row_id,
				r.mfr_doc_id, r.content_id, r.place_id, r.d_plan, p.d_fact,
				f.value, f.value
			from #ms_plan r
				join #ms_fact p on p.mfr_doc_id = r.mfr_doc_id 
					and p.content_id = r.content_id
					and p.place_id = r.place_id
				cross apply dbo.fifo(@fid, p.fact_row_id, p.value, r.plan_row_id, r.value) f
			order by r.plan_row_id, p.fact_row_id

		-- reminds
			insert into #ms_fifo(
				plan_row_id, fact_row_id,
				mfr_doc_id, content_id, place_id, d_plan, d_fact,
				plan_q, fact_q
				)
			select 
				r.plan_row_id, p.fact_row_id, 
				isnull(r.mfr_doc_id, p.mfr_doc_id),
				isnull(r.content_id, p.content_id),
				isnull(r.place_id, p.place_id),
				r.d_plan, p.d_fact,
				f.rq_value, f.pv_value
			from dbo.fifo_reminds(@fid) f
				left join #ms_plan r on r.plan_row_id = f.rq_row_id
				left join #ms_fact p on p.fact_row_id = f.pv_row_id

		-- plan (not in)
			insert into #ms_fifo(plan_row_id, mfr_doc_id, content_id, place_id, d_plan, plan_q)
			select x.plan_row_id, x.mfr_doc_id, x.content_id, x.place_id, x.d_plan, x.value
			from #ms_plan x
			where not exists(select 1 from #ms_fifo where plan_row_id = x.plan_row_id)

		-- fact (not in)
			insert into #ms_fifo(fact_row_id, mfr_doc_id, content_id, place_id, d_plan, d_fact, fact_q)
			select x.fact_row_id, x.mfr_doc_id, x.content_id, x.place_id, x.d_fact, x.d_fact, x.value
			from #ms_fact x
			where not exists(select 1 from #ms_fifo where fact_row_id = x.fact_row_id)

			exec fifo_clear @fid

	-- select * from #ms_fifo where content_id = 11158670
	-- return

	-- save mfr_r_plans_jobs_items_facts
		delete from mfr_r_plans_jobs_items_facts where place_id = @place_id

		insert into mfr_r_plans_jobs_items_facts(place_id, mfr_doc_id, content_id, status_id, d_plan, d_fact, plan_q, fact_q)
		select f.place_id, f.mfr_doc_id, f.content_id, o.status_id, f.d_plan, f.d_fact, f.plan_q, f.fact_q
		from #ms_fifo f
            join (
                select content_id, status_id = min(status_id)
                from sdocs_mfr_opers
                where place_id = @place_id
                group by content_id
            ) o on o.content_id = f.content_id

    exec drop_temp_table '#ms_contents,#ms_contents_fact,#ms_dates,#ms_items'
end
go
