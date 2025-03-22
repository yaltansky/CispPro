if object_id('products_maps_view') is not null drop proc products_maps_view
go
-- exec products_maps_view 1000
create proc products_maps_view
	@mol_id int,	
	-- filter
	@slice varchar(50),
	@search nvarchar(max) = null,
	@folder_id int = null,
	@buffer_operation int = null, 
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	--
	@rowscount int = null out
as
begin

    set nocount on;

    set @search = '%' + replace(@search, ' ', '%') + '%'

	-- pattern params
		declare @pkey varchar(50) = 'ID'
		declare @base_view varchar(50) = 'V_PRODUCTS_MAPS'
		declare @obj_type varchar(16) = 'PMAP'

	-- #ids
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		create table #ids(id int primary key)
		exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'

	-- prepare sql
		declare @sql nvarchar(max), @fields nvarchar(max)

		declare @where nvarchar(max) = concat(
			' where (slice = @slice) '

			-- @search
			, case
				when @search is not null then 'and (x.name like @search or x.product_name like @search)'
			  end
			)

		declare @fields_base nvarchar(max) = N'
			@mol_id int,
			@slice varchar(50),
			@search nvarchar(max)
			'

		declare @join nvarchar(max) = N''
            + case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.id ' else '' end

    -- @rowscount
        set @sql = N'select @rowscount = count(*) from [base_view] x with(nolock) ' + @join + @where
        set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)

        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @slice, @search,
            @rowscount out

        -- @order_by
        declare @order_by nvarchar(100) = N' order by x.name'
        if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			declare @subquery nvarchar(max) = N'(select x.* from [base_view] x with(nolock) '
			    + @join + @where
			    + ' ) x ' + @order_by

    -- @sql
        set @sql = N'select x.* from ' + @subquery
        set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
        
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

        exec sp_executesql @sql, @fields,
            @mol_id, @slice, @search,
            @offset, @fetchrows

end
go
