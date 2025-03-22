if object_id('deal_program_attach') is not null drop procedure deal_program_attach
go
create proc deal_program_attach
	@mol_id int,
	@deal_id int,
	@program_id int
as
begin
	
	set nocount on;
	
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Projects.Programs.Admin')

	if @is_admin = 0
		and exists(select 1 from projects where project_id = @program_id and @mol_id in (chief_id, admin_id))
		set @is_admin = 1

	if @is_admin = 0
	begin
		update deals set program_id = null where deal_id = @deal_id
		raiserror('У Вас нет доступа к модерации состава Программы (Вас необходимо включить в роль Projects.Programs.Admin).', 16, 1)
		return
	end
	
	declare @ids table(deal_id int primary key)
	insert into @ids select @deal_id

	-- check integrity
	if exists(select 1 from projects_tasks where ref_project_id in (select deal_id from @ids) and is_deleted = 0)
	begin
		raiserror('Некоторые из выбранных сделок уже добавлены в программу(-ы). Удалите их из программ(-ы) и повторите операцию.', 11, 1)
		return
	end

	-- add tasks with refs
	insert into projects_tasks(project_id, name, ref_project_id)
	select @program_id, name, project_id
	from projects
	where project_id in (select deal_id from @ids)

	-- set parent_id
	update projects
	set parent_id = @program_id
	where project_id in (select deal_id from @ids)

end
go