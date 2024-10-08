if object_id('app_registry_value') is not null drop function app_registry_value
go
create function [app_registry_value](@registry_id varchar(64))
returns sql_variant as
begin
	return (
		select top 1 
			case 
				when val_number is not null then cast(val_number as sql_variant)
				else cast(val_date as sql_variant)
			end
		from app_registry where registry_id = @registry_id)
end
GO
