if object_id('products_view') is not null drop proc products_view
go
-- exec products_view 1000, @attrs='@id=268&@list=ГОСТ 535-2005++', @buffer_operation = 99
create proc products_view
	@mol_id int,
	-- filter		
	@type_id int = null,
	@class_id int = null,
	@plan_group_id int = null,
	@status_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, 
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
		-- 99 build distinct PRODUCT_ID in buffer
	@search nvarchar(max) = null,
	@attrs varchar(max) = null,
	@attrs_cols varchar(max) = null,
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

	declare @cachetable varchar(50); exec products_builder;2 @mol_id, @cachetable out

	if @buffer_operation = 99 -- virtual value used to build distinct PRODUCT_ID in buffer (see products_view;30)
		set @buffer_operation = null -- clear virtual value for base procedure

	if (@offset = 0 or @buffer_operation is not null)
	begin
		-- select, then cache results		
		exec products_view;10
			@mol_id = @mol_id,
			@type_id = @type_id,
			@class_id = @class_id,
			@plan_group_id = @plan_group_id,
			@status_id = @status_id,
			@folder_id = @folder_id,
			@buffer_operation = @buffer_operation,
			@search = @search,
			@attrs = @attrs,
			@attrs_cols = @attrs_cols,
			@sort_expression = @sort_expression,
			@offset = @offset,
			@fetchrows = @fetchrows,
			@rowscount = @rowscount out,
			@trace = @trace
	end

	-- use cache
	else begin

		declare @sql nvarchar(max) = '
		select x.*
			, A_COL1, A_COL2, A_COL3, A_COL4, A_COL5
			, A_COL6, A_COL7, A_COL8, A_COL9, A_COL10
		from v_products x
			join @cachetable xx on xx.product_id = x.product_id
		order by xx.sort_id
		offset @offset rows fetch next @fetchrows rows only

		set @rowscount = (select count(*) from @cachetable)
		'
		set @sql = replace(@sql, '@cachetable', @cachetable)
		exec sp_executesql @sql, N'@offset int, @fetchrows int, @rowscount int out',
			@offset, @fetchrows, @rowscount out

	end		
end
go
-- hepler: build cache
create proc products_view;10
	@mol_id int,
	-- filter		
	@type_id int = null,
	@class_id int = null,
	@plan_group_id int = null,
	@status_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, 
	@search nvarchar(max) = null,
	@attrs varchar(max) = null,
	@attrs_cols varchar(max) = null,
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	--
	@rowscount int = null out,
	@trace bit = 0
as
begin

	declare @cachetable varchar(50); exec products_builder;2 @mol_id, @cachetable out

	-- @ids
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		declare @ids as app_pkids
		insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'p'

	-- @search_ids	
		declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)

		if exists(select 1 from @search_ids)
			set @search = null
		else begin		
			set @search = '%' + replace(@search, ' ', '%') + '%'		
		end

	begin
		declare @attrs_ids as app_pkids

		if @attrs is not null
		begin
			declare @qattrs nvarchar(max) = 'select product_id from products x where 1=1 '
			declare @exists varchar(100) = ' and exists(select 1 from products_attrs where product_id = x.product_id and attr_id = '

			declare c_attrs cursor local read_only for select item from dbo.str2rows(@attrs, '++') where item is not null
			declare @item nvarchar(1000)

			open c_attrs; fetch next from c_attrs into @item
				while (@@fetch_status <> -1)
				begin
					if (@@fetch_status <> -2)
					begin
						declare @attr_id varchar(50) = dbo.strtoken(dbo.strtoken(@item, '&', 1), '=', 2)
						declare @attr_expr nvarchar(max) = dbo.strtoken(@item, '&', 2)
						declare @condition varchar(max) = dbo.strtoken(@attr_expr, '=', 1)
						declare @condition_params varchar(max) = dbo.strtoken(@attr_expr, '=', 2)

						if @condition = '@search'
							set @qattrs = concat(@qattrs, @exists, @attr_id, ' and attr_value like ''%', @condition_params, '%'')')

						if @condition = '@range' begin
							declare @min float = dbo.strtoken(@condition_params, '-', 1)
							declare @max float = dbo.strtoken(@condition_params, '-', 2)
							if @min is not null
								set @qattrs = concat(@qattrs, @exists, @attr_id, ' and attr_value_number >= ', @min, ')')
							if @max is not null
								set @qattrs = concat(@qattrs, @exists, @attr_id, ' and attr_value_number <= ', @max, ')')
						end

						if @condition = '@list' begin
							declare @items varchar(max) = (
								select '''' + item + ''','  [text()] from  dbo.str2rows(@condition_params, '|')
								for xml path('')
								)
							set @items = substring(@items, 1, len(@items) - 1)
							set @qattrs = concat(@qattrs, @exists, @attr_id, ' and isnull(attr_value, ''[пусто]'') in (', @items, '))')
						end
					end
					fetch next from c_attrs into @item
				end
			close c_attrs; deallocate c_attrs

			if @trace = 1 print concat('qattrs:', @qattrs)
			insert into @attrs_ids exec sp_executesql @qattrs
		end
	end -- filter by @attrs

	-- prepare sql
		declare @sql nvarchar(max), @fields nvarchar(max)

		declare @where_default nvarchar(max) = concat(
			' where (1=1)'
			, case 
				when @status_id = 1000 then '' -- all statuses
				when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')')
				when @folder_id is null then 'and (x.status_id = 5)'
			end
		)

		declare @where nvarchar(max) = concat(
			@where_default
			, case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end
			, case when @class_id is not null then concat(' and (x.class_id = ', @class_id, ')') end
			, case when @plan_group_id is not null then concat(' and (x.plan_group_id = ', @plan_group_id, ')') end
			, case
				when @search is not null then ' and (x.name like @search or x.inner_number = @search)'
			end
			)

		declare @fields_base nvarchar(max) = N'		
			@mol_id int,		
			@search nvarchar(4000),
			@ids app_pkids readonly,	
			@search_ids app_pkids readonly,
			@attrs_ids app_pkids readonly
		'

		declare @inner nvarchar(max) = N''
			+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.product_id ' else '' end
			+ case when exists(select 1 from @search_ids) then ' join @search_ids i2 on i2.id = x.product_id' else '' end
			+ case when @attrs is not null then ' join @attrs_ids i3 on i3.id = x.product_id' else '' end

		if @buffer_operation is  null
		begin
			-- rowscount
				set @sql = N'select @rowscount = count(*) from products x ' + @inner + @where
				set @fields = @fields_base + ', @rowscount int out'

				if @trace = 1 print @sql

				exec sp_executesql @sql, @fields,
					@mol_id, @search,
					@ids, @search_ids, @attrs_ids,
					@rowscount out

			-- order_by
				declare @order_by nvarchar(50) = N' order by product_id'
				if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			-- build cache
				set @sql = replace('truncate table @cachetable', '@cachetable', @cachetable)	
				exec sp_executesql @sql

				if not (
						@where = @where_default 
					and @attrs is null 
					and @attrs_cols is null
					)
				begin
					set @sql = N'
						insert into @cachetable(product_id)
						select @toplimit product_id from products x ' + @inner + @where
					set @fields = @fields_base
						
					set @sql = replace(@sql, '@cachetable', @cachetable)
					set @sql = replace(@sql, '@toplimit', 
						case when @rowscount > 50000 then 'top 50000' else '' end
						)

					exec sp_executesql @sql, @fields,
						@mol_id, @search,
						@ids, @search_ids, @attrs_ids

					-- add custom columns (by attributes)
					if @attrs_cols is not null
					begin
						declare c_attrs_cols cursor local read_only for select top 10 item from dbo.str2rows(@attrs_cols, ',') where item is not null
						declare @i_col int = 1

						open c_attrs_cols; fetch next from c_attrs_cols into @item
							while (@@fetch_status <> -1)
							begin
								if (@@fetch_status <> -2)
								begin
									declare @col_attr_id int = try_parse(@item as int)
									if @col_attr_id is not null
									begin
										set @sql = concat(
											N'update x set a_col', @i_col, ' = pa.attr_value
											from @cachetable x
												join products_attrs pa on pa.product_id = x.product_id and pa.attr_id = ',
											@col_attr_id
											)
										
										set @sql = replace(@sql, '@cachetable', @cachetable)
										exec sp_executesql @sql

										set @i_col = @i_col + 1
									end
								end
								fetch next from c_attrs_cols into @item
							end
						close c_attrs_cols; deallocate c_attrs_cols
					end

					-- sort cache
					declare @sql_sort nvarchar(max) = N'
						update x
						set sort_id = c.sort_id
						from @cachetable x
							join (
								select c.product_id, 
									sort_id = row_number() over (<orderBy>)
								from @cachetable c
									join v_products x on x.product_id = c.product_id
								) c on c.product_id = x.product_id
						'
					set @order_by = replace(@order_by, 'product_id', 'x.product_id')
					set @sql_sort = replace(@sql_sort, '<orderBy>', @order_by)
					set @sql_sort = replace(@sql_sort, '@cachetable', @cachetable)
					exec sp_executesql @sql_sort, N'@mol_id int', @mol_id
					
					set @order_by = ' order by x.sort_id'
				end

			-- select
				if @fetchrows = 0 set @where = ' where 1=0'
				
				declare @subquery nvarchar(max) = N'(
					select x.*
						, a_col1, a_col2, a_col3, a_col4, a_col5
						, a_col6, a_col7, a_col8, a_col9, a_col10
						, xx.sort_id
					from v_products x
						left join @cachetable xx on xx.product_id = x.product_id
					'
					+ @inner + @where +' ) x ' + @order_by

				-- @sql
				set @sql = N'select x.* from ' + @subquery
				set @sql = replace(@sql, '@cachetable', @cachetable)

				-- optimize on fetch
				if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

				set @fields = @fields_base + ', @offset int, @fetchrows int'

				if @trace = 1 print '@sql: ' + @sql + char(10)

				exec sp_executesql @sql, @fields,
					@mol_id, @search,
					@ids, @search_ids, @attrs_ids,
					@offset, @fetchrows
		end

		else begin
			set @rowscount = -1 -- dummy

			declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

			if @buffer_operation in (1,99)
			begin
				if isnull(@attrs,'') = '' and @buffer_operation = 99
				begin
					set @where = ' where exists(select 1 from @cachetable where product_id = x.product_id) ' -- иначе - полный набор
					set @where = replace(@where, '@cachetable', @cachetable)
				end

				-- add to buffer
				set @sql = N'
					delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''P'';
					insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
					select @buffer_id, ''P'', x.product_id, @mol_id from products x '
					+ @inner + @where + 
					';set @rowscount = @@rowcount' +
					';select top 0 * from v_products'
				set @fields = @fields_base + ', @buffer_id int, @rowscount int out'

				exec sp_executesql @sql, @fields,
					@mol_id, @search,
					@ids, @search_ids, @attrs_ids,
					@buffer_id, @rowscount out
			end

			else if @buffer_operation = 2
			begin
				-- remove from buffer
				set @sql = N'
					delete from objs_folders_details
					where folder_id = @buffer_id
						and obj_type = ''P''
						and obj_id in (select product_id from products x ' + @where + ')'
				set @fields = @fields_base + ', @buffer_id int'
				
				exec sp_executesql @sql, @fields,
					@mol_id, @search,
					@ids, @search_ids, @attrs_ids,
					@buffer_id
			end

		end -- buffer_operation
end
go
-- hepler: picker search
create proc products_view;20
	@search varchar(max)
as
begin

	declare @search_inner varchar(100) = @search

	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)
	declare @filter_ids bit = 0

	if exists(select 1 from @search_ids)
	begin
		set @search = null
		set @filter_ids = 1
	end
	else
		set @search = '%' + replace(@search, ' ', '%') + '%'
	
	SELECT TOP 100
		PRODUCT_ID,
		NAME = CONCAT(CASE WHEN STATUS_ID = 10 THEN 'яархив! ' END, p.NAME),
		p.UNIT_ID,
        UNIT_NAME = pu.NAME
	FROM PRODUCTS p
        LEFT JOIN PRODUCTS_UNITS pu on p.UNIT_ID = pu.UNIT_ID
	where status_id >= 0 -- кроме "Удалённых"
		and (
			@search_inner = inner_number
			or (@search is null or p.name like @search)
			)
		and (@filter_ids = 0 or product_id in (select id from @search_ids))
	order by 
		case when @search_inner = inner_number then 0 else 1 end,
		patindex(@search, p.name),
		name

end
go
