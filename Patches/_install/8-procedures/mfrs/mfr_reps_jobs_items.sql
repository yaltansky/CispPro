if object_id('mfr_reps_jobs_pf') is not null drop proc mfr_reps_jobs_pf
if object_id('mfr_reps_jobs_items') is not null drop proc mfr_reps_jobs_items
go
-- exec mfr_reps_jobs_items 700, @folder_id = 98
create proc mfr_reps_jobs_items
	@mol_id int,	
	@plan_id int = null,
	@folder_id int = null -- папка планов
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- @jobs
	declare @jobs as app_pkids

	if @folder_id is not null set @plan_id = null

	if @plan_id is not null insert into @jobs select plan_job_id from mfr_plans_jobs where plan_id = @plan_id and is_deleted = 0
	else insert into @jobs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfj'

	select 
        j.plan_number,
        job_number = j.number,
		j.status_name,
		x.mfr_number,
		j.d_doc,
		item_d_from = xx.oper_d_from,
		x.oper_d_from,
        x.product_name,
        x.item_name,
		place_name = pl1.full_name,
		place_to_name = pl2.full_name,
		x.prev_place_name,        
        oper_name = concat('#', x.oper_number, '-', x.oper_name),
        x.plan_q,
        x.fact_q,
        x.fact_defect_q,        
        note = isnull(x.note, ''),
		plan_job_hid = concat('#', x.plan_job_id),
		item_hid = concat('#', x.item_id),
		oper_hid = concat('#', x.oper_id)
	from v_mfr_plans_jobs_details x		
		join v_mfr_plans_jobs j on j.plan_job_id = x.plan_job_id
			left join mfr_places pl1 on pl1.place_id = j.place_id
			left join mfr_places pl2 on pl2.place_id = j.place_to_id
		join (
			select plan_job_id, item_id, oper_d_from = min(oper_d_from)
			from v_mfr_plans_jobs_details
			group by plan_job_id, item_id
		) xx on xx.plan_job_id = x.plan_job_id and xx.item_id = x.item_id
	where j.plan_job_id in (select id from @jobs)

end
GO
