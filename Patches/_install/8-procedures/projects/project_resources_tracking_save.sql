if object_id('project_resources_tracking_save') is not null drop proc project_resources_tracking_save
go

create proc project_resources_tracking_save
	@mol_id int,
	@tree_id int
as
begin

	set nocount on;

	-- apply manual rebate_shift
	update t
	set d_after = dbo.work_day_add(r.d_from, r.rebate_shift)
	from projects_tasks t
		inner join projects_resources_az_tracking r on r.task_id = t.task_id
	where r.mol_id = @mol_id
		and r.tree_id = @tree_id
		and r.is_manual = 1

	-- calc project
	exec project_tasks_calc @mol_id = @mol_id, @tree_id = @tree_id
	-- calc resource (hot)
	exec project_tasks_calc_resources @tree_id = @tree_id
	-- calc resource analyzer
	exec project_resources_analyze;100 @mol_id = @mol_id, @tree_id = @tree_id
	-- calc overlimits
	exec project_resources_calc_limits @mol_id = @mol_id, @tree_id = @tree_id

end
GO
