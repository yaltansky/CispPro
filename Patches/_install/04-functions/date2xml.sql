if object_id('date2xml') is not null  drop function date2xml
go
CREATE function [date2xml](@date datetime)
returns varchar(50)
as
begin
	--2007-02-19T00:00:00+03:00
	--2007-02-21T14:16:42+03:00
	declare @result varchar(50)

	declare @year char(4) set @year=datepart(year, @date)

	declare @month char(2) set @month=datepart(month, @date)
	if len(@month) = 1 set @month = '0' + @month

	declare @day char(2) set @day=datepart(day, @date)
	if len(@day) = 1 set @day = '0' + @day

	declare @hour char(2) set @hour=datepart(hour, @date)
	if len(@hour) = 1 set @hour = '0' + @hour

	declare @min char(2) set @min=datepart(n, @date)
	if len(@min) = 1 set @min = '0' + @min

	declare @sec char(2) set @sec=datepart(s, @date)
	if len(@sec) = 1 set @sec = '0' + @sec

	set @result = @year + '-' + @month + '-' + @day + 'T' + @hour + ':' + @min + ':' + @sec

	return @result

end



GO
