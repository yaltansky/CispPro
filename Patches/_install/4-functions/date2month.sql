if object_id('date2month') is not null drop function date2month
go
create function date2month(@date datetime)
returns varchar(7)
as
begin
	return (select substring(convert(varchar(10), @date, 20), 1, 7))
end
go
