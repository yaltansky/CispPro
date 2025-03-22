if object_id('mfr_plan_jobs_calc_statuses') is not null drop proc mfr_plan_jobs_calc_statuses
go
/*
	declare @docs app_pkids; insert into @docs select doc_id from mfr_sdocs where plan_status_id = 1
	exec mfr_plan_jobs_calc_statuses @docs = @docs
*/
create proc mfr_plan_jobs_calc_statuses
	@docs app_pkids readonly,
	@mode varchar(20) = 'all', -- all, items, materials
	@tid int = 0
as
begin

	set nocount on;

	create table #jcs_docs(id int primary key)
	insert into #jcs_docs select id from @docs

	exec tracer_log @tid, '    delete "hanged" opers'
		delete x from sdocs_mfr_opers x
		where not exists(select 1 from sdocs_mfr_contents where content_id = x.content_id)

	exec tracer_log @tid, '    граничные случаи'
		update sdocs_mfr_contents
		set status_id = 0
		where mfr_doc_id in (select id from #jcs_docs)
			and isnull(opers_count,0) = 0
			and status_id != 0

		update sdocs_mfr_opers
		set	status_id = 100
		where mfr_doc_id in (select id from #jcs_docs)
			and plan_q = 0
			and isnull(status_id,0) != 100

	-- очистить статус "Проверка"
		if @mode in ('all', 'items')
			update x set status_id = 0
			from sdocs_mfr_contents x
				join #jcs_docs i on i.id = x.mfr_doc_id
			where is_buy = 0
				and status_id = 200

	exec tracer_log @tid, '    статус деталей/материалов'
		update x
		set status_id = 
				case 
					when x.status_id = 200 then
						-- если статус "Проверка", то возможен переход только в "Сделано"
						case when o.status_id = 100 then 100 else 200 end
					else isnull(o.status_id,0)
				end,
			opers_to_fact = case when o.status_id = 100 then o.d_to_fact end,
			opers_fact_q = o.fact_q
		from sdocs_mfr_contents x with(nolock)
			join #jcs_docs i on i.id = x.mfr_doc_id
			join (
				select
					content_id,
					status_id = case when min(status_id) = max(status_id) and min(status_id) = 100 then 100 else min(status_id) end,
					d_to_fact = max(d_to_fact),
					fact_q = min(fact_q)
				from sdocs_mfr_opers with(nolock)
				group by content_id
			) o on o.content_id = x.content_id
		where (
			x.status_id != o.status_id
			or isnull(x.opers_fact_q,0) != isnull(o.fact_q,0)
			)

	exec tracer_log @tid, '    комплекты'
		if @mode in ('all', 'items')
			update x
			set status_id = 
					case
						when not exists(
							select 1 from sdocs_mfr_contents with(nolock) where mfr_doc_id = x.mfr_doc_id
								and product_id = x.product_id
								and node.IsDescendantOf(x.node) = 1
								and is_buy = 0
								and isnull(item_type_id,0) != 12
								and status_id != 100
							) then 100
						else x.status_id
					end
			from sdocs_mfr_contents x with(nolock)
			where x.mfr_doc_id in (select id from #jcs_docs)
				and isnull(x.item_type_id,0) = 12

	exec drop_temp_table '#jcs_docs'

end
go
