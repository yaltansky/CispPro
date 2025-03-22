if object_id('get_nds') is not null 	drop function get_nds
go
create function get_nds() returns float as
begin
	return 0.2
end
GO
