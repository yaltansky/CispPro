if object_id('project_resources_tracking_rollback') is not null drop proc project_resources_tracking_rollback
go
create proc project_resources_tracking_rollback
	@mol_id int,
	@tree_id int
as
begin
	set nocount on;

    update t
    set d_after = track.d_after
    from projects_tasks t
        inner join projects_resources_az_tracking track on track.task_id = t.task_id
    where track.mol_id = @mol_id
        and track.tree_id = @tree_id

	-- calc project
	exec project_tasks_calc @mol_id = @mol_id, @tree_id = @tree_id

	-- calc resource analyzer
	exec project_resources_analyze @mol_id = @mol_id, @tree_id = @tree_id, @recalc = 1;

end
GO
