if object_id('tracer_init') is not null drop proc tracer_init
go
create proc tracer_init
	@trace_name varchar(max), 
	@echo bit = 0,
	@trace_id int out
as
begin
	
	set nocount on;

	if @echo = 1
	begin
		insert into trace_log(trace_name, note, echo) values(@trace_name, 'started', @echo)
		set @trace_id = @@identity

		update trace_log set trace_id = @trace_id where log_id = @trace_id
	end
	else
		set @trace_id = 0
end
GO
