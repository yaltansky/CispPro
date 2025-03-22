if object_id('mfr_wk_sheets_details_calc') is not null drop proc mfr_wk_sheets_details_calc
go
-- exec mfr_wk_sheets_details_calc
create proc mfr_wk_sheets_details_calc
    @trace bit = 0
as
begin
    -- open log
        set nocount on;
        set transaction isolation level read uncommitted;

        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

    -- wk_post_id
        update x set wk_post_id = mols.post_id
        from mfr_wk_sheets_details x
            join mfr_wk_sheets w on w.wk_sheet_id = x.wk_sheet_id
            join mols on mols.mol_id = x.mol_id
        where x.wk_post_id is null
            and w.status_id between 0 and 99

    -- calc metrix
        declare @wk_sheets app_pkids
        insert into @wk_sheets select wk_sheet_id from mfr_wk_sheets where status_id between 0 and 99
        
        exec mfr_wk_sheet_calc;2 @wk_sheets = @wk_sheets

    -- status_id
        update mfr_wk_sheets set status_id = 100 
        where status_id between 0 and 99
            and d_doc < dateadd(d, -7, dbo.today())

	-- close log
        exec tracer_close @tid
        if @trace = 1 exec tracer_view @tid
end
go

