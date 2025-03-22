if object_id('mfr_plan_job_details_summary') is not null drop proc mfr_plan_job_details_summary
go
create proc mfr_plan_job_details_summary
	@plan_job_id int = null
as
begin
	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	select 
		ITEM_ID,
		OPER_KEY = CONCAT(OPER_NUMBER, OPER_NAME),
		NORM_DURATION_WK = (
			select sum(jd.norm_duration_wk * dur1.factor / dur_2.factor)
			from mfr_plans_jobs_details jd
				join projects_durations dur1 on dur1.duration_id = jd.plan_duration_wk_id
				join projects_durations dur_2 on dur_2.duration_id = x.plan_duration_wk_id
			where plan_job_id = x.plan_job_id and item_id = x.item_id and concat(oper_number, oper_name) = concat(x.oper_number, x.oper_name)
			),
		NORM_DURATION_WK_ID = x.PLAN_DURATION_WK_ID,
		PLAN_DURATION_WK = (
			select sum(jd.plan_duration_wk * dur1.factor / dur_2.factor)
			from mfr_plans_jobs_details jd
				join projects_durations dur1 on dur1.duration_id = jd.plan_duration_wk_id
				join projects_durations dur_2 on dur_2.duration_id = x.plan_duration_wk_id
			where plan_job_id = x.plan_job_id and item_id = x.item_id and concat(oper_number, oper_name) = concat(x.oper_number, x.oper_name)
			),
		x.PLAN_DURATION_WK_ID,
		DURATION_WK = (
			select sum(jd.duration_wk * dur1.factor / dur_2.factor)
			from mfr_plans_jobs_details jd
				join projects_durations dur1 on dur1.duration_id = jd.duration_wk_id
				join projects_durations dur_2 on dur_2.duration_id = x.duration_wk_id
			where plan_job_id = x.plan_job_id and item_id = x.item_id and concat(oper_number, oper_name) = concat(x.oper_number, x.oper_name)
			),
		x.DURATION_WK_ID,
		COUNT_EXECUTORS = (
			select count(distinct mol_id)
			from mfr_plans_jobs_executors
			where detail_id in (
				select id from mfr_plans_jobs_details 
				where plan_job_id = x.plan_job_id and item_id = x.item_id and concat(oper_number, oper_name) = concat(x.oper_number, x.oper_name)
				)
				and d_doc is not null
			),
		PROBLEM_NAME = isnull(pm.name, x.note)
	from (
		select
			plan_job_id, item_id, oper_number, oper_name,
			plan_duration_wk_id = min(plan_duration_wk_id),
			duration_wk_id = min(duration_wk_id),
			problem_id = max(problem_id),
			note = max(note)
		from mfr_plans_jobs_details
		where plan_job_id = @plan_job_id
		group by plan_job_id, item_id, oper_number, oper_name
		) x
		left join mfr_plans_jobs_problems_types pm on pm.problem_id = x.problem_id

end
go
