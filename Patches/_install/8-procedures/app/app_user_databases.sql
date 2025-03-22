if object_id('app_user_databases') is not null drop proc app_user_databases
GO
-- exec app_user_databases 1000
create procedure app_user_databases
	@user_id int
as
begin

	declare @databases table(name varchar(30) primary key)

	if exists(select 1 from UsersRoles where UserId = @user_id)
		insert into @databases select name from app_databases
	
	else begin
		declare @subjects app_pkids
		insert into @subjects select distinct ObjectId
		from RolesObjects where MolId = @user_id
			and ObjectType = 'SBJ'

		insert into @databases select name from app_databases
		where name in (select dbname from app_databases_subjects where subject_id in (select id from @subjects))
	end

	-- add default
	insert into @databases select name from app_databases x where is_default = 1
		and not exists(select 1 from @databases where name = x.name)

	select * from app_databases
	where name in (select name from @databases)
        and name in (select name from sys.databases);
end
GO
