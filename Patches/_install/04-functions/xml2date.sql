if object_id('xml2date') is not null drop function xml2date
GO
CREATE function [xml2date](@xml varchar(50))
returns datetime
as
begin
	--2007-02-19T00:00:00+03:00
	--2007-02-21T14:16:42+03:00
	--2009-05-13T14:30:30.873308+04:00
	declare @result datetime
	declare @pos int set @pos = patindex('%+%', @xml)
	if @pos > 0 set @xml = left(@xml, @pos - 1)

	return cast(@xml as datetime)

end
GO
