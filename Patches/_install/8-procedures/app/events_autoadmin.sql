if object_id('events_autoadmin') is not null drop proc events_autoadmin
go
create proc events_autoadmin
as
begin

	IF DB_NAME() NOT IN ('CISP') RETURN

	declare @today datetime = dbo.today()

	-- purge events
		delete from events where datediff(d, add_date, @today) > 30

	-- raise
		exec events_raise

	-- purge UsersLogs
		delete from userslogs
		where datediff(d, TimeStart, getdate()) > 14

		-- declare @endOfMonth datetime = dateadd(month, 1, dateadd(day, -datepart(day, @today), @today))

		-- if @today = @endOfMonth
		-- begin
		-- 	declare @sqlArchiveUsersLog nvarchar(max) = N'
		-- 		select * into cisptmp..UsersLogs%Suffix from UsersLogs;
		-- 		truncate table UsersLogs
		-- 		'
		-- 	set @sqlArchiveUsersLog = replace(@sqlArchiveUsersLog, '%Suffix', convert(varchar, @today, 112))
		-- 	exec sp_executesql @sqlArchiveUsersLog
		-- end

end
go
