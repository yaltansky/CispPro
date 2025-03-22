if object_id('mfr_wk_sheet_jobs_view') is not null drop proc mfr_wk_sheet_jobs_view
go
-- exec mfr_wk_sheet_jobs_view 10872, 2194, 2
create proc mfr_wk_sheet_jobs_view
	@wk_sheet_id int,
	@mol_id int,
	@mode int -- 1 - план, 2 - факт, 3 - очередь
as
begin

	set nocount on;
	set transaction isolation level read uncommitted;

	declare @d_doc date = (select d_doc from mfr_wk_sheets where wk_sheet_id = @wk_sheet_id)

	select 
		W.SUBJECT_ID,
		WJ.PLACE_ID,
		WJ.PLAN_JOB_ID,
        JOB_D_CLOSED = cast(j.d_closed as date),
		JOB_STATUS_NAME = js.name,
		IS_QUEUE = cast(case when wj.exec_status_id != 100 then 1 end as bit),
		PLACE_NAME = pl.name,
		PLACE_NOTE = pl.note,
		MFR_NUMBER = isnull(wj.mfr_number, '-'),
		ITEM_NAME = case when wj.oper_number is null then '[Дополнительные работы]' else p.name end,
		WJ.OPER_DATE,
		OPER_NAME = concat('#', wj.OPER_NUMBER, '-', wj.OPER_NAME),
		RESOURCE_NAME = RS.NAME,
		-- executor info
		e.*
	from mfr_wk_sheets_jobs wj
        join mfr_plans_jobs j on j.plan_job_id = wj.plan_job_id
		join mfr_wk_sheets w on w.wk_sheet_id = wj.wk_sheet_id
		join mfr_plans_jobs_executors e on e.detail_id = wj.detail_id and e.mol_id = @mol_id
		left join mfr_jobs_statuses js on js.status_id = wj.exec_status_id
		left join mfr_places pl on pl.place_id = wj.place_id
		left join products p on p.product_id = nullif(wj.item_id,0)
		left join mfr_resources rs on rs.resource_id = wj.resource_id
	where wj.wk_sheet_id = @wk_sheet_id
		and wj.mol_id = @mol_id
		and (
				(@mode = 1 and wj.d_doc = @d_doc)
			or	(@mode = 2 and wj.d_doc = @d_doc)
			or	(@mode = 3 and wj.exec_status_id != 100)
			)
	order by
		wj.oper_date, pl.name, wj.mfr_number

end
go
