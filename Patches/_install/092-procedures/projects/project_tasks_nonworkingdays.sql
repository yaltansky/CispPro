if object_id('project_tasks_nonworkingdays') is not null drop proc project_tasks_nonworkingdays
go
create proc [project_tasks_nonworkingdays]
	@project_id int
as
begin

	declare @prj_d_from datetime
	select @prj_d_from = isnull(d_from, dbo.today()) from projects where project_id = @project_id

	select day_date from calendar where type = 1
		and day_date >= @prj_d_from

end
GO
