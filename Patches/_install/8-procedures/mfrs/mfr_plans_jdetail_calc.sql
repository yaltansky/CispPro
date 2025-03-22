if object_id('mfr_plans_jdetail_calc') is not null drop proc mfr_plans_jdetail_calc
go
create proc mfr_plans_jdetail_calc
	@details app_pkids readonly,
	@queue_id uniqueidentifier = null
as
begin

	set nocount on;

	create table #jdetail_ids(id int primary key)
		if @queue_id is not null
			insert into #jdetail_ids select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'mco'
		else begin
			insert into #jdetail_ids select id from @details
		end

	EXEC SYS_SET_TRIGGERS 0 -- ВАЖНО ОТКЛЮЧИТЬ триггер, чтобы не было "ленивой" рекурсии

		update e set 
			post_id = isnull(e.post_id, ee.post_id),
			rate_price = isnull(e.rate_price, ee.rate_price),
			note = isnull(e.note, ee.note)
		from mfr_plans_jobs_executors e
			join mfr_plans_jobs_details jd with(nolock) on jd.id = e.detail_id
				join #jdetail_ids i on i.id = jd.id -- filter
				join sdocs_mfr_contents c with(nolock) on c.content_id = jd.content_id
					join mfr_drafts_opers o with(nolock) on o.draft_id = c.draft_id and o.number = jd.oper_number
						join (
							select oper_id, post_id = max(post_id), rate_price = max(rate_price), note = max(note)
							from mfr_drafts_opers_executors with(nolock)
							group by oper_id
						) ee on ee.oper_id = o.oper_id
		where e.post_id is null or e.rate_price is null
		
	EXEC SYS_SET_TRIGGERS 1
	
	declare @jdetail_ids app_pkids; insert into @jdetail_ids select id from #jdetail_ids
	drop table #jdetail_ids

	exec mfr_plan_qjobs_calc_queue @details = @jdetail_ids
end
GO
