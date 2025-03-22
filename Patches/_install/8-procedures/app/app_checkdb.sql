if object_id('app_checkdb') is not null drop proc app_checkdb
go
create proc app_checkdb
as
begin
	
	declare @proc_name varchar(50) = object_name(@@procid)
	declare @message varchar(max)

    if db_name() = 'CISP'
    begin
        -- is_broker_enabled
            if (select is_broker_enabled from sys.databases where name = 'CISP') = 0
            begin
                set @message = 'ERROR: в базе данных CISP отключена опция IS_BROKER_ENABLED.'

                insert into trace_log(trace_name, note, date_start, date_end, is_alert)
                values(@proc_name, @message, getdate(), getdate(), 1)
            end

        -- findocs + findocs_details
            if exists(
                select 1
                from findocs_details d
                    join findocs f on f.findoc_id = d.findoc_id
                group by f.findoc_id, f.value_ccy
                having cast(f.value_ccy - sum(d.value_ccy) as decimal) <> 0
                )
            begin
                set @message = 'ERROR: есть несоответствия findocs + findocs_details.'
                
                insert into trace_log(trace_name, note, date_start, date_end, is_alert)
                values(@proc_name, @message, getdate(), getdate(), 1)
            end
    end

    -- trace_log
    	delete from trace_log where datediff(d, date_start, dbo.today()) > 2

    -- buffer
        delete from objs_folders_details
        where folder_id in (select folder_id from objs_folders where keyword = 'buffer')

    -- queues
	    delete from queues where datediff(d, add_date, dbo.today()) > 2
end
go
