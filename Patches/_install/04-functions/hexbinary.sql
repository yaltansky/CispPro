if object_id('hexbinary') is not null drop function hexbinary
go
create function [hexbinary](@binary varbinary(max))
returns varchar(max) as
begin
	return '0x' + cast('' as xml).value('xs:hexBinary(sql:variable("@binary") )', 'varchar(max)'); 
end
GO
