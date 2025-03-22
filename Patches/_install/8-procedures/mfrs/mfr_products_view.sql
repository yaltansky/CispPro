if object_id('mfr_products_view') is not null drop proc mfr_products_view
go
/*
	declare @r int
	exec mfr_products_view 700, @plan_id = 5, 
		@attr_name='Программа.Гр1',
		@extra_id=-1,
		@rowscount = @r out
*/
create proc mfr_products_view
	@mol_id int,	
	-- filter
	@plan_id int = null,
	@search nvarchar(max) = null,
	@attr_name varchar(50) = null,
	@extra_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, 
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	--
	@rowscount int out
as
begin

    set nocount on;
	set transaction isolation level read uncommitted;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin')

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'p'

-- @search_ids	
	declare @search_text nvarchar(100)
	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)

	declare @search_strict nvarchar(250) = @search

	if exists(select 1 from @search_ids) set @search = null
	else set @search = '%' + replace(@search, ' ', '%') + '%'		

-- @attrs
	declare @attrs as app_pkids
	if @attr_name is not null insert into @attrs select attr_id from mfr_attrs 	where group_name = @attr_name or name = @attr_name

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1)'
		, case when @plan_id is not null then concat(' and (x.plan_id = ', @plan_id, ')') end
		, case when @search is not null then ' and (x.name like @search)' end
		, case when @attr_name is not null and isnull(@extra_id,0) <> -1 then ' and exists(
			select 1 from products_attrs where product_id = x.product_id and attr_id in (select id from @attrs)
			)' end
		, case
			-- Не присвоен атрибут
			when @extra_id = -1 then ' and not exists(
				select 1 from products_attrs
				where product_id = x.product_id and attr_id in (select id from @attrs)
				)'
		  end
		)

	declare @fields_base nvarchar(max) = N'		
		@mol_id int,		
		@search nvarchar(max),
		@ids app_pkids readonly,
		@search_ids app_pkids readonly,
		@attrs app_pkids readonly
	'

	declare @inner nvarchar(max) = N''
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.product_id ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.product_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from v_mfr_plans_products x ' + @inner + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids, @attrs,
            @rowscount out
	
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.name'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'
            (
                SELECT X.* FROM V_MFR_PLANS_PRODUCTS X
			'
            + @inner + @where
            +' ) x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

		-- print @sql

        exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids, @attrs,
            @offset, @fetchrows

	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''p'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''p'', x.product_id, @mol_id from v_mfr_plans_products x '
				+ @inner + @where
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @search,
				@ids, @search_ids, @attrs,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''p''
					and obj_id in (select product_id from v_mfr_plans_products x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @search,
				@ids, @search_ids, @attrs,
				@buffer_id
		end
	end -- buffer_operation

end
go
