if object_id('project_section_getaccess') is not null drop proc project_section_getaccess
go
/***
    declare @access varchar(10)
    exec project_section_getaccess 125, 26078, 'docs', @access out
    select @access
***/
create proc project_section_getaccess
	@mol_id int,
	@project_id int,
	@section varchar(20),
	@access varchar(10) out
as
begin
	
	set @access = '-' -- no access

	-- суперадмин
	if dbo.isinrole(@mol_id, 'Projects.Admin') = 1
		set @access = 'RU'
		
	else if (
		select case when @mol_id in (chief_id, admin_id, curator_id) then 1 end
		from projects where project_id = @project_id
		) = 1
			
		set @access = 'RU'

	else begin
		declare @section_id int = (select section_id from projects_sections where ikey = @section)
		select @access = 
					isnull(case when s.a_read = 1 then 'R' end, '') +
					isnull(case when s.a_update = 1 then 'U' end, '')
		from projects_mols_sections s
		where s.project_id = @project_id 				
			and s.mol_id = @mol_id
			and s.section_id = @section_id
	end


end
GO
