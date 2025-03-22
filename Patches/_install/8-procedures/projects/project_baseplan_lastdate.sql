if object_id('project_baseplan_lastdate') is not null drop proc project_baseplan_lastdate
go
create proc project_baseplan_lastdate
	@project_id int
as
begin

	set nocount on;

	declare @id int

	select @id = max(id) from reglament_hist
	where [key] = 'projects/' + cast(@project_id as varchar)
		and action = 'SaveBasePlan'

	select * from reglament_hist
	where id = @id

end
go
