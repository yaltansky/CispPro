if object_id('mfr_plans_rates_view') is not null drop proc mfr_plans_rates_view
go
-- exec mfr_plans_rates_view 1000
create proc mfr_plans_rates_view
	@mol_id int,	
	-- filter
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
	@rowscount int = null out,
	@trace bit = 0
as
begin

  set nocount on;
	set transaction isolation level read uncommitted;

	declare @today datetime = dbo.today()

-- pattern params
	declare @pkey varchar(50) = 'ID'
	declare @base_view varchar(50) = 'V_MFR_PLANS_RATES'
	declare @obj_type varchar(16) = 'MFRATE'

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type

-- @search
	set @search = '%' + @search + '%'
-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1)'
		, case when @d_doc_from is not null then ' and (x.d_doc >= @d_doc_from)' end
		, case when @d_doc_to is not null then ' and (x.d_doc <= @d_doc_to)' end

		, case
			when @search is not null then ' and (x.product_group_name like @search)'
		  end
		)
			
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,				
		@d_doc_from datetime,
		@d_doc_to datetime,
		@search nvarchar(max),		
		@ids app_pkids readonly
	'

	declare @join nvarchar(max) = N''
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.[pkey] ' else '' end
		
	if @buffer_operation is null
	begin
		-- @rowscount
			set @sql = N'select @rowscount = count(*) from [base_view] x ' + @join + @where
			set @fields = @fields_base + ', @rowscount int out'

			set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
			if @trace = 1 print 'count: ' + @sql

			exec sp_executesql @sql, @fields,
				@mol_id, @d_doc_from, @d_doc_to, @search, @ids,
				@rowscount out
	
		-- @order_by
			declare @order_by nvarchar(50) = N' order by x.product_group_name, x.d_doc'
			if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			declare @subquery nvarchar(max) = N'(select x.* from [base_view] X '
				+ @join + @where
				+ ') x ' + @order_by

        -- @sql
        	set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        	if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'
	        set @fields = @fields_base + ', @offset int, @fetchrows int'
		
        set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
		if @trace = 1 print 'select: ' + @sql

		exec sp_executesql @sql, @fields,
            @mol_id, @d_doc_from, @d_doc_to, @search, @ids,
            @offset, @fetchrows

	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
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

		print @fields

		exec sp_executesql @sql, @fields,
			@mol_id, @d_doc_from, @d_doc_to, @search, @ids,
			@buffer_id
	
	end -- buffer_operation

end
go
