if object_id('datediff_wh') is not null  drop function datediff_wh
go
CREATE function [datediff_wh](@start_date datetime, @end_date datetime)
--функция возвращает длительность рабочего времени, находящееся между двумя датами
returns datetime
as
begin

  declare
    @start_work_time datetime,
    @end_work_time datetime,
    @start_date_day datetime,
    @end_date_day datetime,
    @res datetime

  select @start_date_day = dbo.getday(@start_date),
         @end_date_day = dbo.getday(@end_date),
         @start_work_time = dateadd(hour, 9, cast(0 as datetime)) +
                          dateadd(minute, 30, cast(0 as datetime)),
         @end_work_time = dateadd(hour, 18, cast(0 as datetime))+
                        dateadd(minute, 30, cast(0 as datetime)),
         @res = 0

  --для каждого дня таблицы CALENDAR
  --в отрезке [@start_date; @end_date] находим длину пересечения отрезков
  --[DAY_DATE+@start_work_time; DAY_DATE+@end_work_time]
  --[@start_date; @end_date]
  --и затем суммируем эти длины

  select @res = sum(cast(
	case when day_date + @end_work_time <= @start_date or
         day_date + @start_work_time >= @end_date then 0
    else case when day_date + @end_work_time <= @end_date 
              then day_date + @end_work_time
              else @end_date end-
         case when day_date + @start_work_time >= @start_date 
              then day_date + @start_work_time
              else @start_date end 
    end as float
	))
  from calendar
  where type = 0
	and day_date between @start_date_day and @end_date_day

  return @res
end
GO
