if object_id('mfr_wk_sheets_details_buffer_action') is not null drop proc mfr_wk_sheets_details_buffer_action
go
create proc mfr_wk_sheets_details_buffer_action
	@mol_id int,
	@action varchar(32),
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids
        if @queue_id is not null
            insert into @buffer select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfw'
        else
            insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfw')

	declare @docs app_pkids

    BEGIN TRY

        if @action = 'Calc'
        begin
            print 'noing'
        end

    END TRY
    BEGIN CATCH
        declare @errtry varchar(max) = error_message()
        raiserror (@errtry, 16, 3)
    END CATCH

    -- trace end
        exec tracer_close @tid
end
GO
