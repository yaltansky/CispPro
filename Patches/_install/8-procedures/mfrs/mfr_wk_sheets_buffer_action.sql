if object_id('mfr_wk_sheets_buffer_action') is not null drop proc mfr_wk_sheets_buffer_action
go
create proc mfr_wk_sheets_buffer_action
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
            declare c_wks cursor local read_only for 
                select wk_sheet_id from mfr_wk_sheets
                where wk_sheet_id in (select id from @buffer)
                order by d_doc, wk_sheet_id
            declare @wk_sheet_id int

            open c_wks; fetch next from c_wks into @wk_sheet_id
                while (@@fetch_status != -1)
                begin
                    if (@@fetch_status != -2) exec mfr_wk_sheet_calc @wk_sheet_id = @wk_sheet_id
                    fetch next from c_wks into @wk_sheet_id
                end
            close c_wks; deallocate c_wks
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
