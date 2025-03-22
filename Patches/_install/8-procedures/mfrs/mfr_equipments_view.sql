if object_id('mfr_equipments_view') is not null drop proc mfr_equipments_view
go
-- exec mfr_equipments_view 1000, @subject_id = 37
create proc mfr_equipments_view
	@mol_id int,	
	-- filter
	@subject_id int = null,
	@status_id int = null,
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@folder_id int = null,
	@buffer_operation int = null,
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
	@search nvarchar(max) = null,
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	--
	@rowscount int = null out
as
begin

    set nocount on;
	set transaction isolation level read uncommitted;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin')

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfe'


-- @search_ids
	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)
	
	if exists(select 1 from @search_ids) set @search = null
	else set @search = '%' + replace(@search, ' ', '%') + '%'		

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1)'
		, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
		, case 
			when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')')
			when @folder_id is not null then '' -- all statuses
			else ' and (x.status_id <> -1)'
		  end
		, case when @search is not null then ' and (x.content like @search)' end
		)
			
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,				
		@search nvarchar(max),		
		@ids app_pkids readonly,
		@search_ids app_pkids readonly		
	'

	declare @join nvarchar(max) = N''
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.equipment_id ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.equipment_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from v_mfr_equipments x ' + @join + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids,
            @rowscount out
	
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.equipment_id'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'(select x.* from v_mfr_equipments X '
            + @join + @where
            + ') x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

		print @sql

        exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids,
            @offset, @fetchrows

	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''MFE'';
				;insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''MFE'', x.equipment_id, @mol_id from v_mfr_equipments x '
				+ @join + @where
				+ ';select top 0 * from v_mfr_equipments'
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @search,
				@ids, @search_ids,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''MFE''
					and obj_id in (select equipment_id from v_mfr_equipments x ' + @where + ')
				; select top 0 * from v_mfr_equipments'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @search,
				@ids, @search_ids,
				@buffer_id
		end
	end -- buffer_operation

end
go
