if object_id('project_baseplan_save') is not null drop proc project_baseplan_save
go
create proc project_baseplan_save
	@project_id int,
	@mol_id int
as
begin

	set nocount on;

	update projects_tasks
	set base_d_from = d_from,
		base_d_to = d_to
	where project_id = @project_id

	insert into reglament_hist([key], mol_id, action, note)
	values('projects/' + cast(@project_id as varchar), @mol_id, 'SaveBasePlan', 'Сохранён базовый план')

end
go
