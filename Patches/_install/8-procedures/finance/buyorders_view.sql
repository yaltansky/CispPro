if object_id('buyorders_view') is not null drop proc buyorders_view
go
-- exec buyorders_view 1000
create proc buyorders_view
	@mol_id int,
	-- filter		
	@subject_id int = null,	
	@status_id int = null,	
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@agent_id int = null,
	@manager_id int = null,
	@search nvarchar(max) = null,
	@extra_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, -- 1 add rows to buffer, 2 remove rows from buffer
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

	if (@offset = 0 or @buffer_operation is not null)
		or not exists(select 1 from sdocs_cache where mol_id = @mol_id)
	begin
	-- select, then cache results		
		exec buyorders_view;10
			@mol_id = @mol_id,			
			@subject_id = @subject_id,
			@status_id = @status_id,
			@d_doc_from = @d_doc_from,
			@d_doc_to = @d_doc_to,
			@manager_id = @manager_id,
			@search = @search,
			@extra_id = @extra_id,
			@folder_id = @folder_id,
			@buffer_operation = @buffer_operation,
			@sort_expression = @sort_expression,
			@offset = @offset,
			@fetchrows = @fetchrows,
			@rowscount = @rowscount out,
			@trace = @trace
	end

	-- use cache
	else begin
		select x.*
		from supply_buyorders x
			join sdocs_cache xx on xx.mol_id = @mol_id and xx.doc_id = x.doc_id
		order by xx.id
		offset @offset rows fetch next @fetchrows rows only

		set @rowscount = (select count(*) from sdocs_cache where mol_id = @mol_id)
	end
end
GO

create proc buyorders_view;10
	@mol_id int,
	-- filter	
	@subject_id int = null,
	@status_id int = null,
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@manager_id int = null,
	@search nvarchar(max) = null,
	@extra_id int = null,
	@folder_id int = null,
	@buffer_operation int = null,
	@sort_expression varchar(50) = null,	
	@offset int = 0,
	@fetchrows int = 30,	
	@cacheonly bit = 0,
	--
	@rowscount int out,
	@trace bit = 0
as
begin

-- access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	
	declare @ids as app_pkids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'buyorder'

-- cast @search
	declare @doc_id int
		
	if dbo.hashid(@search) is not null
	begin
		set @doc_id = dbo.hashid(@search)
		set @search = null
	end
	else begin
		set @search = '%' + @search + '%'
	end

	declare @today datetime = dbo.today()

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		N' where 
				(@doc_id is null or x.doc_id = @doc_id) 
			and (x.subject_id in (select id from @subjects))
			'
		, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
		, case when @manager_id is not null then concat(' and (x.mol_id = ', @manager_id, ')') end
		
		, case 
			when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
			when exists(select 1 from @ids) then ''
			else ' and (x.status_id >= 0)'
		  end
				
		, case when @d_doc_from is not null then ' and (x.d_doc >= @d_doc_from)' end
		, case when @d_doc_to is not null then ' and (x.d_doc <= @d_doc_to)' end
		
		-- @search
		, case
			when @search is not null then 'and (
				x.content like @search
				or exists(
					select 1 from sdocs_products
					where doc_id = x.doc_id
						and product_id in (select product_id from products where name like @search)
					)
			)'
		  end
		)

	declare @fields_base nvarchar(max) = N'
		@mol_id int,
		@today datetime,
		@d_doc_from datetime,
		@d_doc_to datetime,
		@search nvarchar(max),
		@doc_id int,	
		@subjects app_pkids readonly,		
		@ids app_pkids readonly
	'

	declare @inner nvarchar(max) = N''
		+ case when @folder_id is null then '' else ' join @ids ids on ids.id = x.doc_id ' end
		
	if @buffer_operation is not null
	begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''BUYORDER'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''BUYORDER'', x.doc_id, @mol_id from sdocs x '
				+ @inner + @where
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @today, @d_doc_from, @d_doc_to,
				@search, @doc_id,
				@subjects, @ids,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''BUYORDER''
					and obj_id in (select doc_id from sdocs x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @today, @d_doc_from, @d_doc_to,
				@search, @doc_id,
				@subjects, @ids,
				@buffer_id
		end
	end

	else 
	begin
		-- @rowscount
		if @cacheonly = 0
		begin
			set @sql = N'select @rowscount = count(*) from supply_buyorders x ' + @inner + @where
			set @fields = @fields_base + ', @rowscount int out'

			if @trace = 1 print 'count(*): ' + @sql + char(10)

			exec sp_executesql @sql, @fields,
				@mol_id, @today, @d_doc_from, @d_doc_to,
				@search, @doc_id,
				@subjects, @ids,
				@rowscount out
		end
		
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.doc_id'

		if @sort_expression is not null
		begin
			if charindex('value_ccy', @sort_expression) = 1 begin
				set @sort_expression = replace(@sort_expression, 'value_ccy', 'abs(value_ccy)')
				set @sort_expression = @sort_expression + ', d_doc'
			end
			set @order_by = N' order by ' + @sort_expression
		end

		delete from sdocs_cache where mol_id = @mol_id

		declare @subquery nvarchar(max) = N'(select x.* from supply_buyorders x '
			+ @inner + @where
			+ ' ) x ' + @order_by

		-- cache
		if isnull(@rowscount,0) < 5000 or @cacheonly = 1
		begin			
			declare @sql_cache nvarchar(max) = N'
				insert into sdocs_cache(mol_id, doc_id)
				select @mol_id, x.doc_id
				from ' + @subquery
			set @fields = @fields_base

			exec sp_executesql @sql_cache, @fields,
				@mol_id, @today, @d_doc_from, @d_doc_to,
				@search,  @doc_id,
				@subjects, @ids				
		end

		if @cacheonly = 0
		begin
			-- @sql
			set @sql = N'select x.* from ' + @subquery

			-- optimize on fetch
			if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

			set @fields = @fields_base + ', @offset int, @fetchrows int'

			if @trace = 1 print '@sql: ' + @sql + char(10)

			exec sp_executesql @sql, @fields,
				@mol_id, @today, @d_doc_from, @d_doc_to,
				@search, @doc_id,
				@subjects, @ids,
				@offset, @fetchrows
		end

	end -- if

end
go
