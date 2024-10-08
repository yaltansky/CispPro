if object_id('mfr_draft_items_view') is not null drop proc mfr_draft_items_view
go
-- exec mfr_draft_items_view 700, 1384
create proc [mfr_draft_items_view]
	@mol_id int,	
	-- filter
	@draft_id int,
	@is_material bit = null,
	@extra_id int = null,
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

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin')

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'P'

-- @search_ids
	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)
	
	set @search = replace(replace(@search, '[', ''), ']', '')

	if exists(select 1 from @search_ids) set @search = null
	else set @search = '%' + replace(@search, ' ', '%') + '%'		

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (x.draft_id = ', @draft_id, ') '
		, case when isnull(@is_material,0) = 0 
			then ' and (x.is_buy = 0)'
			else ' and (x.is_buy = 1)'
		  end
		, case
			when @search is not null then ' and (x.item_name like @search) '
		  end
		)
			
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,				
		@search nvarchar(max),		
		@ids app_pkids readonly,
		@search_ids app_pkids readonly		
	'

	declare @join nvarchar(max) = N''
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.draft_id ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.draft_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from v_sdocs_mfr_drafts_items x ' + @join + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids,
            @rowscount out
	
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.draft_id'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'(select x.* from v_sdocs_mfr_drafts_items X '
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
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''P'';
				;insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''P'', x.item_id, @mol_id from v_sdocs_mfr_drafts_items x '
				+ @join + @where
				+ ';select top 0 * from v_sdocs_mfr_drafts_items'
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
					and obj_type = ''P''
					and obj_id in (select item_id from v_sdocs_mfr_drafts_items x ' + @where + ')
				; select top 0 * from v_sdocs_mfr_drafts_items'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @search,
				@ids, @search_ids,
				@buffer_id
		end
	end -- buffer_operation

end
GO
