﻿if object_id('budgets_reglament') is not null drop proc budgets_reglament
go
create proc budgets_reglament
	@mol_id int,
	@for_update bit = 0
as
begin

	set nocount on;

	declare @roles_names varchar(500) = 'Findocs.Subjects.Admin,Findocs.Subjects.Moderator'
	if @for_update = 0 set @roles_names = @roles_names + ',Findocs.Subjects.Reader'

	declare @roles app_pkids
	insert into @roles select id from roles where name in (
		select item from dbo.str2rows(@roles_names, ',')
		)

	declare @subjects table(subject_id int)
	declare @budgets table(budget_id int)

-- subjects by roles
	insert into @subjects
	select ObjectId from RolesObjects
	where RoleId in (select id from @roles)
		and MolId = @mol_id
		and ObjectType = 'SBJ'

	if dbo.isinrole(@mol_id, 'admin') = 1
		-- by role
		or exists(
			select 1 from UsersRoles
			where RoleId in (select id from roles where charindex(name, @roles_names) > 0)
				and UserId = @mol_id
			)
	begin
		insert into @subjects(subject_id) select subject_id from subjects
		insert into @budgets(budget_id) select -1 -- all budgets
	end

-- by subjects
	if exists(select 1 from @subjects)		
	begin
		insert into @budgets(budget_id) select -1 -- all budgets
	end

-- allowed budgets (if not all)
	if not exists(select 1 from @budgets where budget_id = -1)
		insert into @budgets 
		select distinct x.budget_id 
		from budgets_shares x
			join budgets b on b.budget_id = x.budget_id
		where x.mol_id = @mol_id
			and x.a_read = 1

-- @result
	declare @result as app_objects

	-- subjects
	insert @result(obj_type, obj_id) select distinct 'SBJ', subject_id from @subjects		
	
	-- budgets
	insert @result(obj_type, obj_id) select distinct 'BDG', budget_id from @budgets

	select * from @result where @mol_id <> 0
end
go
