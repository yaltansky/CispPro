if object_id('app_registry_varchar') is not null drop function app_registry_varchar
go
create function [app_registry_varchar](@registry_id varchar(64))
returns varchar(max) as
begin
	return (select top 1 val_string from app_registry where registry_id = @registry_id)
end
GO
