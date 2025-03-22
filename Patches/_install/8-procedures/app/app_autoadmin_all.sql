if object_id('app_autoadmin_all') is not null drop proc app_autoadmin_all
go
create proc app_autoadmin_all
as
begin
    set nocount on;

    declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
        declare @tid_msg varchar(max)

	declare c_databases cursor local read_only for
        select name from app_databases where name not like '%test%'
    declare @dbname varchar(64)
	
	open c_databases; fetch next from c_databases into @dbname
		while (@@fetch_status != -1)
		begin
			if (@@fetch_status != -2)
			begin
                begin try
                    set @tid_msg = concat(@dbname, ' started')
                    exec tracer_log @tid, @tid_msg
                        declare @sql nvarchar(max) = concat('exec ', @dbname, '..app_autoadmin')
                        exec sp_executesql @sql
                end try
                begin catch
                    declare @err varchar(max) = error_message()
                    raiserror (@err, 16, 3)
                end catch
			end
			--
			fetch next from c_databases into @dbname
		end
	close c_databases; deallocate c_databases

    exec tracer_close @tid
end
go
