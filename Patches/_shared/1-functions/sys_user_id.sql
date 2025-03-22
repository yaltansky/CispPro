if object_id('sys_user_id') is not null drop function sys_user_id
GO
create function sys_user_id()
returns int as
begin
	return cast(context_info() as xml).value('(/user/@id)[1]', 'int')
end
GO
