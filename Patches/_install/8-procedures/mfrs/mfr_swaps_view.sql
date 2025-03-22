if object_id('mfr_swaps_view') is not null drop proc mfr_swaps_view
go
-- exec mfr_swaps_view 700, @trace = 1
create proc mfr_swaps_view
	@mol_id int,	

	-- filter
	@subject_id int = null,
	@status_id int = null,
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
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
	@rowscount int = null out,
	@trace bit = 0
as
begin

  set nocount on;
	set transaction isolation level read uncommitted;

-- pattern params
	declare @pkey varchar(50) = 'DOC_ID'
	declare @base_view varchar(50) = 'MFR_SWAPS'
	declare @obj_type varchar(3) = 'SWP'

	declare @today datetime = dbo.today()

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type

-- @search_ids
	declare @search_ids as app_pkids; insert into @search_ids select distinct id from dbo.hashids(@search)
	declare @search_attr bit = 0

	set @search = replace(replace(@search, '[', ''), ']', '')

	if substring(@search, 1, 1) = ':' begin
		set @search_attr = 1
		set @search = substring(@search, 2, 255)
	end		

	if exists(select 1 from @search_ids) set @search = null
	else set @search = '%' + replace(@search, ' ', '%') + '%'

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1) '
		, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
		, case when @status_id is not null 
				then ' and (x.status_id = @status_id)' 
				else ' and (x.status_id <> -1)' 
			end
		, case when @d_doc_from is not null then ' and (x.d_doc >= @d_doc_from)' end
		, case when @d_doc_to is not null then ' and (x.d_doc <= @d_doc_to)' end
		, case when @search is not null then ' and (
				x.content like @search
				or exists(
					select 1 from sdocs_products
					where doc_id = x.doc_id
						and (
                            product_id in (select product_id from products where name like @search)
							or mfr_number like @search
							or note like @search
							or errors like @search
							)
					)
				)
			' end
		)
			
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,		
		@today datetime,
		@d_doc_from datetime,
		@d_doc_to datetime,
		@status_id int,
		@search nvarchar(max),		
		@ids app_pkids readonly,
		@search_ids app_pkids readonly
	'

	declare @join nvarchar(max) = N''
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.doc_id ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.doc_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from [base_view] x ' + @join + @where
        set @fields = @fields_base + ', @rowscount int out'

		set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
        exec sp_executesql @sql, @fields,
            @mol_id, @today, @d_doc_from, @d_doc_to, @status_id, @search,
            @ids, @search_ids,
            @rowscount out
	
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.[pkey]'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'(SELECT X.* FROM [base_view] X '
            + @join + @where
            + ') x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

		set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
		if @trace = 1 print @sql

        exec sp_executesql @sql, @fields,
            @mol_id, @today, @d_doc_from, @d_doc_to, @status_id, @search,
            @ids, @search_ids,
            @offset, @fetchrows
	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id
		set @fields = @fields_base

		exec objs_buffer_viewhelper
			@buffer_operation = @buffer_operation,
			@obj_type = @obj_type,
			@base_view = @base_view,
			@pkey = @pkey,
			@join = @join,
			@where = @where,
			@fields = @fields out,
			@sql = @sql out			

		exec sp_executesql @sql, @fields,
			@mol_id, @today, @d_doc_from, @d_doc_to, @status_id, @search,
			@ids, @search_ids,
			@buffer_id

	end -- buffer_operation

end
go
