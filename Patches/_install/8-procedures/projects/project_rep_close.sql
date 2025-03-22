if object_id('project_rep_close') is not null drop proc project_rep_close
go

create proc [dbo].[project_rep_close]
	@report_id int
as
begin

	set nocount on;

-- change status
	update projects_reps 
	set status_id = 10
	where rep_id = @report_id
end
go