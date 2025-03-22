if object_id('drop_temp_table') is not null drop proc drop_temp_table
go
create proc drop_temp_table
	@temp_table_names varchar(max)
as
begin

	declare c_tables cursor local read_only for
		select distinct item from dbo.str2rows(@temp_table_names,',')
			
	declare @temp_table_name sysname
	
	open c_tables; fetch next from c_tables into @temp_table_name
		while (@@fetch_status <> -1)
		begin
			if (@@fetch_status <> -2)
			begin
				begin try

					set @temp_table_name = ltrim(rtrim(@temp_table_name))

					if object_id(concat('tempdb.dbo.', @temp_table_name)) is not null
					begin
						declare @sql nvarchar(500) = concat(N'drop table ', @temp_table_name)
						exec sp_executesql @sql
					end
					
				end try
				begin catch end catch
			end
			fetch next from c_tables into @temp_table_name
		end
	close c_tables; deallocate c_tables
	
end
GO
