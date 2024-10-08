if object_id('work_day_diff_core') is not null drop function work_day_diff_core
GO
create function [work_day_diff_core] (@d_from datetime, @d_to datetime) 
returns int
as
begin

	if @d_from = @d_to
		return 1

	declare @result int = (
		select count(*) - 1
		from calendar 
		where day_date between @d_from and @d_to
			and type = 0 
		)

	return @result
end
GO
