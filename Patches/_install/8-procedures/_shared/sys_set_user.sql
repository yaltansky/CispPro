if object_id('sys_set_user') is not null drop proc sys_set_user
GO
create proc sys_set_user @user_id int as
begin
	declare @xml xml = isnull(cast(context_info() as xml), '')
	set @xml.modify('delete /user')
	set @xml.modify('insert <user id="{sql:variable("@user_id")}"/> into .')

	declare @context varbinary(128) = cast(cast(@xml as char(128)) as varbinary(128))
	set context_info @context
end
GO
