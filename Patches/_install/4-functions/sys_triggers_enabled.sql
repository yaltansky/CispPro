if object_id('sys_triggers_enabled') is not null drop function sys_triggers_enabled
GO
create function sys_triggers_enabled()
returns bit as
begin
	return cast(context_info() as xml).value('(/trigger/@on)[1]', 'bit')
end
GO
