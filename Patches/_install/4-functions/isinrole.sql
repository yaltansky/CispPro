if object_id('isinrole') is not null drop function isinrole
go
create function isinrole(@mol_id int, @roles varchar(max))
returns bit
as begin

	set @roles = ',' + @roles + ','
	
	return 
		case 
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
				) 
				then 1
			else 0
		end
end
GO
