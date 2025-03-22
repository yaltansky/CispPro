if object_id('tracer_view') is not null drop proc tracer_view
go
create proc tracer_view @trace_id int
as
begin
	
	set nocount on;

	update x
	set date_end = l.next_start
	from trace_log x
		join (
			select 
				log_id,
				next_start = lead(date_start, 1, null) over (partition by trace_id order by log_id)
			from trace_log
		) l on l.log_id = x.log_id


	select trace_name, note, date_diff = cast(datediff(ms, date_start, date_end)/1000. as decimal(10,2))
		into #view
	from trace_log where trace_id = @trace_id order by log_id

	select trace_name, note, 
		date_diff = 
			case 
				when note = 'completed!' then (select sum(date_diff) from #view)
				else date_diff
			end
	from #view

	drop table #view
end
go
