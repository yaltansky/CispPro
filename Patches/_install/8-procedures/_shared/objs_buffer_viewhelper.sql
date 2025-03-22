if object_id('objs_buffer_viewhelper') is not null drop proc objs_buffer_viewhelper
go
create proc objs_buffer_viewhelper
	@buffer_operation int,
	@obj_type varchar(16),
	@base_view varchar(50),
	@pkey varchar(32),	
	@join nvarchar(max),
	@where nvarchar(max),
	@fields nvarchar(max) out,
	@sql nvarchar(max) out
as
begin
	
	if @buffer_operation = 1
	begin
		-- add to buffer
		set @sql = N'
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''[obj_type]'';
			;insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, ''[obj_type]'', x.[pkey], @mol_id from [base_view] x with(nolock) '
			+ @join + @where
			+ ';select top 0 * from [base_view]'
		set @fields = @fields + ', @buffer_id int'

		set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
	end

	else if @buffer_operation = 2
	begin
		-- remove from buffer
		set @sql = N'
			delete from objs_folders_details
			where folder_id = @buffer_id
				and obj_type = ''[obj_type]''
				and obj_id in (select [pkey] from [base_view] x ' + @where + ')
			; select top 0 * from [base_view]'
		set @fields = @fields + ', @buffer_id int'
			
		set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
	end

end
GO