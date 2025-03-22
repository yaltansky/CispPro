if object_id('sys_set_triggers') is not null drop proc sys_set_triggers
GO
create proc sys_set_triggers @on_off bit as
begin
	declare @xml xml = isnull(cast(context_info() as xml), '')
	set @xml.modify('delete /trigger')
	set @xml.modify('insert <trigger on="{sql:variable("@on_off")}"/> into .')
	
	declare @context varbinary(128) = cast(cast(@xml as char(128)) as varbinary(128))
	set context_info @context
end
GO
