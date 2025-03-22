if object_id('project_get_sections') is not null
	drop proc project_get_sections
GO

create proc project_get_sections
	@project_id int,
	@mol_id int
as
begin

	set nocount on;

	declare @type_id int = (select type_id from projects where project_id = @project_id)

	declare @projects_sections table(section_id int, divider_after bit)
		insert into @projects_sections(section_id, divider_after)
		select 
			section_id,
			case
				when @type_id = 1 then divider_after
				else 0
			end
		from projects_sections
		where @type_id = 1
			or (@type_id = 2 and is_program = 1)
			or (@type_id = 3 and is_deal = 1)

	declare @sections table(section_id int)
	
	declare @chief_id int, @admin_id int, @curator_id int
		select @chief_id = chief_id, @admin_id = admin_id, @curator_id = curator_id
		from projects where project_id = @project_id

	if dbo.isinrole(@mol_id, 'Projects.Admin') = 1
		or @mol_id in (@chief_id, @admin_id, @curator_id)
	begin
		insert into @sections select section_id from projects_sections
	end

	else begin

		insert into @sections 
			select section_id from projects_mols_sections 
			where project_id = @project_id
				and mol_id = @mol_id
				and a_read = 1

	end

	select 
		x.SECTION_ID, NAME,
		replace(HREF, '{id}', @project_id) as HREF,
		CSS, CSS_LI, IS_DEFAULT, IS_REQUIRED,
		xx.DIVIDER_AFTER,
		x.SORT_ID
	from projects_sections x
		inner join @projects_sections xx on xx.section_id = x.section_id
	where x.section_id in (select section_id from @sections)
	order by sort_id

end
GO
