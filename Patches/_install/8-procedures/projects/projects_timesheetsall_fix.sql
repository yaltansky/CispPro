if object_id('projects_timesheetsall_fix') is not null drop proc projects_timesheetsall_fix
go
create proc projects_timesheetsall_fix
	@user_id int,
	@mol_id int,
	@project_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@search nvarchar(100) = null,
	@fix_state bit
as
begin

    set nocount on;
	
	set @search = '%' + replace(@search, ' ', '%') + '%'
	declare @is_admin bit = 1

	update x
	set fixed_date = case when @fix_state = 1 then getdate() end,
		fixed_mol_id = @user_id
	from projects_timesheets_days x
		join projects_timesheets ts on ts.timesheet_id = x.timesheet_id
			join projects p on p.project_id = ts.project_id
	where (@is_admin = 1 or @user_id in (p.chief_id, p.admin_id))
		and (ts.mol_id = @mol_id)
		and (@project_id is null or ts.project_id = @project_id)
		and (@d_from is null or x.d_doc >= @d_from)
		and (@d_to is null or x.d_doc <= @d_to)
		and (@search is null or ts.name like @search)

end
go
