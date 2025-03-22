if object_id('date2str') is not null drop function date2str
go
create function date2str(@date datetime, @date_style smallint = 20)
returns varchar(20)
as
begin
	declare @ret varchar(20)
	
	if @date_style = 20
		set @ret = substring(convert(varchar, @date, @date_style), 1, 10)
	else 
		set @ret = convert(varchar, @date, @date_style)
	
	return @ret
end
go
