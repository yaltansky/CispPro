if object_id('date2qrt') is not null  drop function date2qrt
go
create function [date2qrt](@date datetime)
returns int
as
begin
	
	return cast(
			cast(datepart(yyyy, @date) as char(4)) + cast(datepart(q,@date) as char(1))
			as int)

end
GO
