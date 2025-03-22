if object_id('projects_timesheets_calc') is not null drop proc projects_timesheets_calc
go
create proc projects_timesheets_calc
	@project_id int = null,
	@mol_id int = null
as begin

	set nocount on;

BEGIN TRY
BEGIN TRANSACTION

	-- projects_timesheets
	insert into projects_timesheets(mol_id, project_id, task_id, name)
		select rx.mol_id, x.project_id, x.task_id, substring(x.name, 1, 250)
		from projects_tasks x
			join projects_tasks_raci rx on rx.task_id = x.task_id
		where (@project_id is null or x.project_id = @project_id)
			and raci like '%R%'
			and x.is_deleted = 0
			and (@mol_id is null or rx.mol_id = @mol_id)
			and not exists(select 1 from projects_timesheets where mol_id = rx.mol_id and project_id = x.project_id and task_id = x.task_id)

		-- + TASKS.PROJECT_TASK_ID
		insert into projects_timesheets(mol_id, project_id, task_id, name)
			select distinct tm.mol_id, x.project_id, x.task_id, substring(x.name, 1, 250)
			from projects_tasks x
				join tasks t on t.project_task_id = x.task_id
					join tasks_mols tm on tm.task_id = t.task_id and role_id = 1
			where (@project_id is null or x.project_id = @project_id)
				and (@mol_id is null or tm.mol_id = @mol_id)
				and not exists(select 1 from projects_timesheets where mol_id = tm.mol_id and project_id = x.project_id and task_id = x.task_id)

	-- projects_timesheets
	insert into projects_timesheets_mols(project_id, mol_id)
		select distinct x.project_id, x.mol_id
		from projects_timesheets x
		where (@project_id is null or x.project_id = @project_id)
			and (@mol_id is null or x.mol_id = @mol_id)
			and not exists(select 1 from projects_timesheets_mols where project_id = x.project_id and mol_id = x.mol_id)

	declare @today datetime = dbo.today()
		
	update x
	set sum_plan_h = pt.duration_wk / nullif(dur.factor,0),
		sum_fact_h = (select sum(fact_h) from projects_timesheets_days where timesheet_id = x.timesheet_id and isnull(is_deleted,0) = 0),
		d_deadline = isnull(pt.d_before, pt.d_to)
	from projects_timesheets x
		join projects_tasks pt on pt.task_id = x.task_id
		join projects_durations dur on dur.duration_id = 2 -- часы
	where (@project_id is null or x.project_id = @project_id)
			and (@mol_id is null or x.mol_id = @mol_id)

	declare @totals table(
		project_id int, mol_id int, plan_h decimal(18,2), fact_h decimal(18,2)
		primary key (project_id, mol_id)
		)

		insert into @totals (project_id, mol_id, plan_h, fact_h)
		select ts.project_id, ts.mol_id, 
			isnull(max(ts.sum_plan_h), sum(d.plan_h)),
			sum(d.fact_h)
		from projects_timesheets ts 
			join projects_timesheets_days d on d.timesheet_id = ts.timesheet_id
		where (@project_id is null or ts.project_id = @project_id)
			and (@mol_id is null or ts.mol_id = @mol_id)
		group by ts.project_id, ts.mol_id

	update x
	set sum_plan_h = (select sum(plan_h) from @totals where project_id = p.project_id and mol_id = x.mol_id),
		sum_fact_h = (select sum(fact_h) from @totals where project_id = p.project_id and mol_id = x.mol_id),
		sum_allexcept_plan_h = (select sum(plan_h) from @totals where project_id <> p.project_id and mol_id = x.mol_id),
		sum_allexcept_fact_h = (select sum(fact_h) from @totals where project_id <> p.project_id and mol_id = x.mol_id)
	from projects_timesheets_mols x
		join projects p on p.project_id = x.project_id
	where (@project_id is null or x.project_id = @project_id)
		and (@mol_id is null or x.mol_id = @mol_id)

	update x set calc_date = getdate()
	from projects_timesheets x
	where (@project_id is null or project_id = @project_id)
		and (@mol_id is null or mol_id = @mol_id)

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max) set @err = error_message()
	raiserror (@err, 16, 1)
END CATCH

end
GO
