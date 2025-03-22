if object_id('deal_program_detach') is not null drop procedure deal_program_detach
go
create proc deal_program_detach
	@mol_id int,
	@deal_id int
as
begin
	
	set nocount on;
	
	declare @program_id int = (select parent_id from projects where project_id = @deal_id)

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Projects.Programs.Admin')

	if @is_admin = 0
		and exists(select 1 from projects where project_id = @program_id and @mol_id in (chief_id, admin_id))
		set @is_admin = 1

	if @is_admin = 0
	begin
		raiserror('У Вас нет доступа к модерации состава Программы.', 16, 1)
		return
	end
	
	declare @ids table(deal_id int primary key)
	insert into @ids select @deal_id

	-- remove tasks with refs
	delete x 
	from projects_tasks x
		join projects p on p.project_id = x.project_id and p.type_id = 2
	where ref_project_id in (select deal_id from @ids)

	-- set parent_id
	update projects
	set parent_id = null
	where project_id in (select deal_id from @ids)

end
go