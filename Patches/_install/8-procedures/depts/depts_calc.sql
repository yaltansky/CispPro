if object_id('depts_calc') is not null drop proc depts_calc
go
create proc depts_calc
    @trace bit = 0
as
begin

	update depts set node = '/'
    
    exec tree_calc_nodes 'depts', 'dept_id',
		@sortable = 0,
        @trace = @trace

end
GO
