if object_id('projects_pivots_timesheets_planfact') is not null drop proc projects_pivots_timesheets_planfact
go
-- exec projects_pivots_timesheets_planfact 700, 1000
go
create proc projects_pivots_timesheets_planfact
	@user_id int,
	@project_id int = null,
	@mol_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
    @trace bit = 0
as
begin

	set nocount on;

	create table #result(
		project_id int,
		task_id int index ix_task,
		task_name varchar(500),
		mol_id int index ix_mol,
		d_deadline datetime,
		d_doc datetime,
		plan_h decimal(18,2),
		fact_h decimal(18,2),
		event_name varchar(50),
		note varchar(max)
		)

	declare @section_isadmin int = (select top 1 section_id from projects_sections where ikey = 'mols')

	create table #admins(
		project_id int,
		admin_id int,
		primary key (project_id, admin_id)
		)
		insert into #admins(project_id, admin_id)
		select project_id, admin_id = mol_id
		from projects_mols_sections x
		where section_id = @section_isadmin
			and mol_id = @user_id
			and a_update = 1

	insert into #result(project_id, task_id, task_name, d_deadline, d_doc, mol_id, plan_h, fact_h, event_name, note)
	select x.project_id, x.task_id, x.task_name, x.d_deadline, x.d_doc, x.mol_id, x.plan_h, x.fact_h, x.event_name, x.note
	from projects_timesheetsall_days x
		join projects p on p.project_id = x.project_id
		left join #admins sa on sa.project_id = x.project_id
	where (@project_id is null or x.project_id = @project_id)
		and (@mol_id is null or x.mol_id = @mol_id)
		and (@d_from is null or x.d_doc >= @d_from)
		and (@d_to is null or x.d_doc <= @d_to)
		and (x.plan_h > 0 or x.fact_h > 0)
		and (
			@user_id in (x.mol_id, p.chief_id, p.curator_id, p.admin_id, isnull(sa.admin_id,0)) 
			)

	select
		project_name = p.name,
		x.task_name,
		t.progress,
		t.d_to,
		t.d_before,
		t.d_to_fact,
		x.event_name,
		mol_name = mols.name,
		x.d_doc,
		d_doc_week = datepart(iso_week, x.d_doc),
		d_doc_month = datepart(month, x.d_doc),
		x.note,
		x.plan_h,
		plan_v = x.plan_h * pm.hourly_rate,
		x.fact_h,
		fact_v = x.fact_h * pm.hourly_rate,
		x.project_id,
		x.task_id,
		x.mol_id
	from #result x
		join projects p on p.project_id = x.project_id
			left join (
                select project_id, mol_id, hourly_rate = max(hourly_rate)
                from projects_mols
                group by project_id, mol_id
            ) pm on pm.project_id = p.project_id and pm.mol_id = x.mol_id
		join projects_tasks t on t.task_id = x.task_id
		join mols on mols.mol_id = x.mol_id

	exec drop_temp_table '#admins,#result'

end
GO
