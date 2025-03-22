if object_id('tracer_log') is not null drop proc tracer_log
go
create proc tracer_log
	@trace_id int,
	@note varchar(max),
	@level int = 0
as
begin
	if @trace_id != 0
	begin
		if @level > 0 set @note = left('....................', @level * 4) + @note
		insert into trace_log(trace_id, note) values(@trace_id, @note)
		-- print @note
	end
end
GO
