if object_id('queue_process_manual') is not null drop proc queue_process_manual
go
create proc [queue_process_manual]
as
begin
	set nocount on;

	declare c_stages cursor local read_only for 
        select id, sql_cmd
        from queues
        where add_date >= dbo.today()
            and dbname = db_name()
            and process_start is null
			and sql_cmd not like 'rmq%'
        order by id

	declare @id int, @sql_cmd nvarchar(max)
	
	open c_stages; fetch next from c_stages into @id, @sql_cmd
		while (@@fetch_status <> -1)
		begin
			if (@@fetch_status <> -2)
			begin			
				update queues set process_start = getdate() where id = @id
				begin try
					exec sp_executesql @sql_cmd
					update queues set process_end = getdate() where id = @id
				end try

				begin catch
					update queues set process_end = getdate(), errors = error_message() where id = @id
				end catch
			end
			--
			fetch next from c_stages into @id, @sql_cmd
		end
	close c_stages; deallocate c_stages

end
GO
