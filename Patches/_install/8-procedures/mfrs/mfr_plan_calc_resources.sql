if object_id('mfr_plan_calc_resources') is not null drop proc mfr_plan_calc_resources
go
-- exec mfr_plan_calc_resources 700
-- select * from mfr_plans_resources_fifo
create proc mfr_plan_calc_resources
	@mol_id int,
	@plan_id int = null,
	@trace bit = 0
as
begin

	set nocount on;

begin

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
		' @mol_id=', @mol_id,
		' @plan_id=', @plan_id
		)
	exec tracer_log @tid, @tid_msg

	-- @plans
	declare @plans as app_pkids
	
	if isnull(@plan_id,0) = 0
		insert into @plans select plan_id from mfr_plans where status_id = 1
	else
		insert into @plans select @plan_id

	-- @docs
	declare @docs as app_pkids
	insert into @docs select doc_id from sdocs where plan_id in (select id from @plans)

end -- params

begin

	create table #opers(
		oper_id int primary key,
		plan_id int,
		calendar_id int,
		resource_id int,	
		oper_after datetime,
		oper_from datetime,
		oper_to datetime,
		duration float,
		duration_id int,
		value float
		)

	create table #opers_days(
		oper_row_id int identity primary key,
		plan_id int,
		resource_id int,		
		oper_id int,
		oper_date datetime,
		value float,
		index ix_opers(plan_id, resource_id, oper_id, oper_date)
		)

	create table #resources(
		res_row_id int identity primary key,
		plan_id int,
		resource_id int,
		resource_date datetime,
		value float,
		index ix_resources(plan_id, resource_id, resource_date)		
		)
		
	create table #result(		
		oper_row_id int index ix_oper_row,
		res_row_id int index ix_job_row,
		plan_id int,
		resource_id int,
		resource_date datetime,
		oper_id int index ix_oper,
		plan_q float,
		fact_q float,
		slice varchar(20),
		index ix_result(plan_id, oper_id)
		)

	declare @fid uniqueidentifier set @fid = newid()

end -- tables

begin
	exec tracer_log @tid, 'FIFO'

	-- #opers
		insert into #opers(plan_id, calendar_id, resource_id, oper_id, oper_after, oper_from, oper_to, duration, duration_id, value)
		select 
			sd.plan_id, isnull(pl.calendar_id,1), dr.resource_id, x.oper_id, x.d_after, dbo.getday(x.d_from), dbo.getday(x.d_to), x.duration, x.duration_id, x.plan_q * dr.loading
		from sdocs_mfr_opers x
			join sdocs_mfr_contents c on c.content_id = x.content_id
				join sdocs_mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = x.number
					join sdocs_mfr_drafts_opers_resources dr on dr.oper_id = do.oper_id
			join sdocs sd on sd.doc_id = x.mfr_doc_id
				join mfr_plans pl on pl.plan_id = sd.plan_id
		where x.mfr_doc_id in (select id from @docs)
			and c.is_deleted = 0
		
	-- #opers_days
		insert into #opers_days(plan_id, resource_id, oper_id, oper_date, value)
		select o.plan_id, o.resource_id, o.oper_id, x.day_date, value
		from #opers o
			cross apply calendar x
		where x.day_date between o.oper_from and o.oper_to
			and (o.calendar_id <> 1 or (o.calendar_id = 1 and x.type <> 1))
		order by o.plan_id, o.resource_id, x.day_date, o.oper_id

	-- #resources
		declare @plan_dates table(plan_id int, resource_id int, calendar_id int, d_from datetime, d_to datetime, limit_q float)
		insert into @plan_dates(plan_id, resource_id, calendar_id, d_from, d_to, limit_q)
		select o.plan_id, o.resource_id, isnull(pl.calendar_id,1), min(o.oper_from), max(o.oper_from) + 365, max(res.limit_q)
		from #opers o
			join projects_resources res on res.resource_id = o.resource_id
			join mfr_plans pl on pl.plan_id = o.plan_id
		group by o.plan_id, o.resource_id, pl.calendar_id

		insert into #resources(plan_id, resource_id, resource_date, value)
		select pd.plan_id, pd.resource_id, x.day_date, pd.limit_q
		from @plan_dates pd
			cross apply calendar x
		where x.day_date between pd.d_from and pd.d_to
			and (pd.calendar_id <> 1 or (pd.calendar_id = 1 and x.type <> 1))
		order by pd.plan_id, pd.resource_id, x.day_date

	-- FIFO
	insert into #result(
		oper_row_id, res_row_id,
		plan_id, resource_id, oper_id, resource_date, 
		plan_q, fact_q, slice
		)
	select 
		r.oper_row_id, p.res_row_id,
		r.plan_id, p.resource_id, r.oper_id, p.resource_date,
		f.value, f.value, 'mix'
	from #opers_days r
		join #resources p on p.plan_id = r.plan_id and p.resource_id = r.resource_id and p.resource_date >= r.oper_date
		cross apply dbo.fifo(@fid, p.res_row_id, p.value, r.oper_row_id, r.value) f
	order by r.oper_row_id, p.res_row_id

	exec fifo_clear @fid
end -- FIFO

begin

-- mfr_plans_resources_fifo
	delete from mfr_plans_resources_fifo where plan_id in (select id from @plans)

	insert into mfr_plans_resources_fifo(
		resource_id, resource_date, plan_id, mfr_doc_id, content_id, item_id, oper_id, oper_place_id, oper_from, oper_to, loading
		)
	select
		r.resource_id, r.resource_date, r.plan_id, o.mfr_doc_id, o.content_id, c.item_id, o.oper_id, o.place_id, o.d_from, o.d_to, r.fact_q
	from #result r
		join sdocs_mfr_opers o on o.oper_id = r.oper_id
			join sdocs_mfr_contents c on c.content_id = o.content_id

-- sdocs_mfr_opers_resources_limits
	delete from sdocs_mfr_opers_resources_limits where plan_id in (select id from @plans)
	
	insert into sdocs_mfr_opers_resources_limits(
		plan_id, oper_id, resource_id, res_from, res_to
		)
	select 
		plan_id, oper_id, resource_id, res_from, res_to
	from (
		select 
			r.plan_id, r.oper_id, r.resource_id,
			oper_from = min(o.oper_from),
			oper_to = max(o.oper_to),
			res_from = min(resource_date),
			res_to = max(resource_date),
			res_duration = datediff(d, min(resource_date), max(resource_date)),
			oper_duration = datediff(d, min(o.oper_from), max(o.oper_to))
		from #result r
			join #opers o on o.oper_id = r.oper_id
		group by r.plan_id, r.oper_id, r.resource_id
		) t
	where res_from > oper_from
		or res_duration > oper_duration

end -- results

finish:

-- close log
	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid

-- drop mfr_plan_jobs_calcs
	if object_id('tempdb.dbo.#opers') is not null drop table #opers
	if object_id('tempdb.dbo.#resources') is not null drop table #resources
	if object_id('tempdb.dbo.#result') is not null drop table #result

end
GO
