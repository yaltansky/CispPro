if object_id('sys_table_getseedscript') is not null drop proc sys_table_getseedscript
GO
create proc [sys_table_getseedscript]
	@table_name sysname,
	@where varchar(max) = null
	-- , @seedscript varchar(max) out
as
begin
	
	declare @last_column int = (select max(column_id) from sys.columns where object_id = object_id(@table_name))
	declare c_columns cursor local read_only for 
		select name, user_type_id, column_id from sys.columns where object_id = object_id(@table_name) order by column_id

	declare @name sysname, @type int, @column_id int
	declare @sql varchar(max) = 
';set indentity_insert ' + @table_name + ' on;' + char(10) +
'insert into ' + @table_name + ' values'  + char(10)

	declare @sql_values nvarchar(max) = N'select @values = @values + ''('''

	open c_columns
	fetch next from c_columns into @name, @type, @column_id

	while (@@fetch_status <> -1)
	begin
		if (@@fetch_status <> -2)
		begin
			if @type = 167
				set @sql_values = @sql_values + ' + '''''''' + ' + @name
			else if @type = 61
				set @sql_values = @sql_values + ' + '''''''' + convert(varchar,' + @name + ', 20)'
			else 
				set @sql_values = @sql_values + ' + cast(' + @name + ' as varchar)'

			if @column_id = @last_column
			begin
				if @type in (61, 167)
					set @sql_values = @sql_values + '+'''''')'''
				else
					set @sql_values = @sql_values + '+'')'''

				set @sql_values	= @sql_values + '+'','' + char(10)'
			end	
			else begin
				if @type in (61, 167)
					set @sql_values = @sql_values + ' + '''''',''' + char(10)
				else 
					set @sql_values = @sql_values + '+'',''' + char(10)
			end

		end

		fetch next from c_columns into @name, @type, @column_id
	end

	close c_columns
	deallocate c_columns
		
	set @sql_values = @sql_values + ' from ' + @table_name
	if @where is not null set @sql_values = @sql_values + ' where ' + @where

	declare @values varchar(max) = ''
	exec sp_executesql @sql_values, N'@values varchar(max) out', @values out

	set @values = substring(@values, 1, len(@values) - 2)
	
	set @sql = @sql + @values + char(10)
	+ ';set indentity_insert ' + @table_name + ' off;'

	print @sql
end
GO
