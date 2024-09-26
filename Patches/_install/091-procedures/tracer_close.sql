if object_id('tracer_close') is not null drop proc tracer_close
go
CREATE proc [tracer_close] @trace_id int
as
begin
	exec tracer_log @trace_id, 'completed!'
end


GO
