if object_id('work_day_add') is not null drop function work_day_add
GO
CREATE function [work_day_add] (@d_from datetime, @days int) 
returns datetime
as
begin

-- Находим ближайший рабочий день
	declare @id int

	select top 1 @id = workday_id
	from calendar where workday_id is not null
		and day_date >= @d_from
	order by id

	declare @res datetime

-- @id + @days (с учётом знака) - искомый день
	select @res = day_date from calendar
	where workday_id = @id + @days -- поскольку workday_id - непрерыная индексация только рабочих дней

-- если что-то за пределами календаря
	if @res is null set @res = dateadd(d, @days, @d_from)

	return @res
end
GO
