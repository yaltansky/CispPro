if object_id('calendar_calc') is not null drop proc calendar_calc
go
-- exec calendar_calc '2025-01-01'
create proc calendar_calc
	@date_start datetime = null,
	@date_end datetime = null
as
begin
	set nocount on;
	
	declare @last_date datetime = (select max(day_date) from calendar)
	declare @date datetime = isnull(@last_date, @date_start)
	if @date_end is null set @date_end = dateadd(year, 3, @date)

	if exists(select 1 from calendar where day_date = @date_end)
		return -- nothing todo

-- @date_start
	declare @loop int; set @loop = 1

	while @date <= @date_end and @loop < 10000
	begin
		insert into calendar(day_date, type)
		values(@date, case when datepart(dw, @date) in (1,7) then 1 else 0 end)

		set @date = @date + 1
		set @loop = @loop + 1
	end

-- WORKDAY_ID
	declare @calendar table (id int, day_date datetime)
	insert into @calendar(id, day_date)
	select
		row_number() over (order by day_date) as id
		, day_date
	from calendar
	where type = 0

	update c
	set workday_id = cc.id
	from calendar c
		inner join @calendar cc on cc.day_date = c.day_date
	where c.workday_id is null

end
GO

exec calendar_calc '2024-01-01', '2030-12-31'
GO
