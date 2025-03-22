if object_id('mfr_getobjects') is not null drop proc mfr_getobjects
go
-- exec mfr_getobjects 700
-- exec mfr_getobjects 1507 	 	
create proc mfr_getobjects
	@mol_id int,
	@for_update bit = 0
as
begin
	set nocount on;
	
	declare @roles_names varchar(max) = 'Mfr.Admin,Mfr.Admin.Materials,Mfr.Moderator,Mfr.Moderator.Materials,Mfr.Wksheets.Moderator'
	if @for_update = 0 set @roles_names = @roles_names + ',Mfr.Reader,Mfr.Reader.Materials'

	declare @roles app_pkids
	insert into @roles select id from roles where name in (
		select item from dbo.str2rows(@roles_names, ',')
		)

	declare @subjects table(subject_id int)

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
	end

-- @result
	declare @result as app_objects
	insert @result(obj_type, obj_id) select distinct 'SBJ', subject_id from @subjects		

	select * from @result
end
go
