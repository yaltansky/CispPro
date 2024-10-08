if object_id('work_day_diff') is not null drop function work_day_diff
GO
CREATE function [work_day_diff] (@d_from datetime, @d_to datetime) 
returns int
as
begin

	declare @result int

	if @d_from = @d_to
		return 0

	select @result = count(*) - 1
	from calendar 
	where day_date between @d_from and @d_to
		and type = 0 

	return @result
end



GO
