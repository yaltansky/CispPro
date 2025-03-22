if object_id('isinrole_byobjs') is not null drop function isinrole_byobjs
go
create function isinrole_byobjs(
	@mol_id int,
	@roles varchar(max),
	@object_type varchar(16) = null,
	@object_ids varchar(max) = null
)
returns bit
as begin

	set @roles = ',' + @roles + ','
	
	declare @ids app_pkids
	if @object_ids is not null
		insert into @ids select item from dbo.str2rows(@object_ids, default)

	return 
		case 
			when dbo.isinrole(@mol_id, 'admin') = 1
				then 1
			when 
				(charindex('admin', @roles) > 0 and @mol_id = -25)
				or exists(
					select 1 from UsersRoles
					where RoleId in (select id from roles where charindex(',' + name + ',', @roles) > 0)
						and UserId = @mol_id
				)
				or exists(
					select 1 from RolesObjects x
					where RoleId in (select id from roles where charindex(',' + name + ',', @roles) > 0)
						and MolId = @mol_id
						and (@object_type is null or (
							ObjectType = @object_type and 1 = all(
								select 
									case 
										when exists(select 1 from RolesObjects where RoleId = x.RoleId and ObjectType = @object_type and ObjectId = i.id) then 1
										else 0
									end
								from @ids i
								)
						))
				) 
				then 1
			else 0
		end
end
GO
