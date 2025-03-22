if object_id('mfr_reps_opers_pf') is not null drop proc mfr_reps_opers_pf
go
-- exec mfr_reps_opers_pf 1000, 16
-- exec mfr_reps_opers_pf 1000, null, 19600
create proc mfr_reps_opers_pf
	@mol_id int,	
	@plan_id int = null,
	@folder_id int = null
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- @plans
	declare @plans as app_pkids

	if @folder_id is not null set @plan_id = null

	if @plan_id = 0 insert into @plans select plan_id from mfr_plans where status_id = 1
	else if @plan_id is not null insert into @plans select @plan_id
	else insert into @plans exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

	select 
		x.mfr_doc_id,
		x.product_id,
		x.content_id,
		x.oper_id,
		vendor_name = '-',
		place_name = concat(pl.name, ' ', pl.note),
		place_to_name = concat(pl2.name, ' ', pl2.note),
		x.mfr_number,
		d_delivery = sd.d_delivery,
		product_name = p.name,
		milestone_name = isnull(x.milestone_name, ''),
		item_type_name = '-',
		x.item_name, 
		oper_name = x.name,		
		completion = cast(
			case 				
				when x.plan_q <= x.fact_q then '5-Сделано' 
				when x.fact_q > 0 then '4-Частично' 
			end
			as varchar(30)),
		x.plan_q,
		x.fact_q,
		x.d_to, 
		x.d_to_predict,
		x.d_to_fact,
		diff_predict = datediff(d, x.d_to, x.d_to_predict),
		diff_fact = datediff(d, x.d_to, x.d_to_fact),
		mfr_doc_hid = concat('#', x.mfr_doc_id),
        product_hid = concat('#', x.product_id),
		item_hid = concat('#', c.item_id)
	into #result
	from sdocs_mfr_opers x
		join sdocs sd on sd.doc_id = x.mfr_doc_id
		join sdocs_mfr_contents c on c.content_id = x.content_id
		left join dbo.mfr_places pl on pl.place_id = x.place_id
		left join dbo.sdocs_mfr_opers op2 on op2.oper_id = x.next_id
			left join dbo.mfr_places pl2 on pl2.place_id = op2.place_id
		join products p on p.product_id = x.product_id
		join products p2 on p2.product_id = x.product_id
	where (x.work_type_id = 1)
		-- reglament access
		and sd.subject_id in (select id from @subjects)
		-- conditions
		and sd.plan_id in (select id from @plans)

	create index ix_result1 on #result(mfr_doc_id, product_id)
	create index ix_result2 on #result(content_id)

	update x set completion = '3-Выполняется'
	from #result x
	where completion is null
		and exists(
				select 1 from mfr_plans_jobs_details jd 
					join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
				where j.status_id = 2
					and oper_id = x.oper_id
			) 

	update x set completion = '2-Планируется'
	from #result x
	where completion is null
		and exists(
				select 1 from mfr_plans_jobs_details jd 
					join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
				where j.status_id in (0,1)
					and oper_id = x.oper_id
			)

	update #result set completion = '1-Нет заданий'
	where completion is null

	select * from #result
	drop table #result
end
GO
