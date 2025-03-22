if object_id('tasks_analyzers_view') is not null
	drop proc tasks_analyzers_view
go
create proc tasks_analyzers_view
	@owner_type varchar(16),
	@owner_id int,
	@search varchar(max) = null
as
begin

	set nocount on;

	declare @mols table(mol_id int)

	declare @agent_id int = case when @owner_type = 'agents' then @owner_id end
	declare @project_id int = case when @owner_type = 'projects' then @owner_id end
	declare @payorder_id int = case when @owner_type = 'payorders' then @owner_id end

	if @agent_id is not null
	begin
		insert into @mols
			select admin_id from agents where agent_id = @agent_id and admin_id is not null

		insert into @mols
			select distinct mol_id
			from agents_mols
			where agent_id = @agent_id
	end

	else if @project_id is not null
	begin
		insert into @mols
			select curator_id from projects where project_id = @project_id
			union
			select chief_id from projects where project_id = @project_id

		insert into @mols
			select distinct mol_id
			from projects_mols
			where project_id = @project_id
				and mol_id is not null
	end

	else if @payorder_id is not null
	begin
		insert into @mols
			select r.MolId from RolesObjects r where r.ObjectType = 'SBJ' 
				and r.ObjectId = (select subject_id from payorders where payorder_id = @payorder_id)
				and r.RoleId in (select Id from Roles where Name in ('Findocs.Subjects.Moderator'))
			union 
			select UserId from UsersRoles
			where RoleId in (select Id from Roles where Name in ('Findocs.Subjects.Moderator'))
	end

	select
		MOL_ID, NAME, DEPT_ID, POST_ID, IS_WORKING, EMAIL, STATUS_ID
	from mols
	where mol_id in (select mol_id from @mols)
		and (@search is null or name like @search + '%')
	order by name

end
go
