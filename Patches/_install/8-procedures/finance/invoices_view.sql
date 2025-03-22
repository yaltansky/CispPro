if object_id('invoices_view') is not null drop proc invoices_view
go
-- exec invoices_view 1000
create proc invoices_view
	@mol_id int,
	-- filter		
	@acc_register_id int = null,	
	@subject_id int = null,	
	@status_id int = null,	
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@dates_id int = null,	
	@agent_id int = null,	
	@author_id int = null,	
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
		exec invoices_view;10
			@mol_id = @mol_id,			
			@acc_register_id = @acc_register_id,
			@subject_id = @subject_id,
			@status_id = @status_id,
			@author_id = @author_id,
			@d_doc_from = @d_doc_from,
			@d_doc_to = @d_doc_to,
			@dates_id = @dates_id,
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
		from supply_invoices x
			join sdocs_cache xx on xx.mol_id = @mol_id and xx.doc_id = x.doc_id
		order by xx.id
		offset @offset rows fetch next @fetchrows rows only

		set @rowscount = (select count(*) from sdocs_cache where mol_id = @mol_id)
	end
end
GO
-- helper: build selection
create proc invoices_view;10
	@mol_id int,
	-- filter	
	@acc_register_id int = null,
	@subject_id int = null,
	@status_id int = null,
	@author_id int = null,
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@dates_id int = null,
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

    declare @today datetime = dbo.today()

    -- pattern params
        declare @pkey varchar(50) = 'DOC_ID'
        declare @base_view varchar(50) = 'SUPPLY_INVOICES'
        declare @obj_type varchar(16) = 'INV'

    -- access
        declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
        create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'sbj'
        
        create table #ids(id int primary key)
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
        exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'

    -- #search_ids
        create table #search_ids(id int primary key); insert into #search_ids select distinct id from dbo.hashids(@search)
        if exists(select 1 from #search_ids) begin
            set @search = null
            set @status_id = null
        end
        else set @search = '%' + replace(@search, ' ', '%') + '%'

	-- #products
		create table #products(id int primary key)
		if @search is not null and len(@search) > 4
		begin
			insert into #products select product_id from products where name like @search
			-- if exists(select 1 from #products) set @search = null
		end

    -- prepare sql
        declare @sql nvarchar(max), @fields nvarchar(max)

        declare @where nvarchar(max) = concat(
            N' where (x.subject_id is null or x.subject_id in (select id from #subjects))
                '
            , case when @acc_register_id is not null then concat(' and (x.acc_register_id = ', @acc_register_id, ')') end
            , case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
            , case when @author_id is not null then concat(' and (x.mol_id = ', @author_id, ')') end
            
            , case 
                when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
                when exists(select 1 from #ids) or exists(select 1 from #search_ids) then ''
                else ' and (x.status_id >= 0)'
            end
            
            , case when @d_doc_from is not null or @d_doc_to is not null then 
                case
                    when isnull(@dates_id,0) = 1 then ' and (x.d_doc between isnull(@d_doc_from,x.d_doc) and isnull(@d_doc_to,x.d_doc))'
                    when isnull(@dates_id,0) = 2 then ' and (x.d_delivery between isnull(@d_doc_from,x.d_delivery) and isnull(@d_doc_to,x.d_delivery))'
                    when @dates_id = 100 then ' and (x.add_date between isnull(@d_doc_from,x.add_date) and isnull(dateadd(d,1,@d_doc_to),x.add_date))'
                    when @dates_id = 101 then ' and (x.update_date between isnull(@d_doc_from,x.update_date) and isnull(@d_doc_to,x.update_date))'
                end
              end
            
			-- @search
			, case
					when @search is not null then ' and (
                        x.content like @search
						or exists(
							select 1 from sdocs_products sp with(nolock)
								join #products p on p.id = sp.product_id
							where doc_id = x.doc_id
							)
                        )'
				end
            )

        declare @fields_base nvarchar(max) = N'
            @mol_id int,
            @today datetime,
            @d_doc_from datetime,
            @d_doc_to datetime,
            @search nvarchar(max)
        '

        declare @join nvarchar(max) = N''
            + case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.doc_id ' else '' end
            + case when exists(select 1 from #search_ids) then 'join #search_ids i2 on i2.id = x.doc_id' else '' end
            
        if @buffer_operation is not null
        begin
            set @rowscount = -1 -- dummy
            set @fields = @fields_base

            declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

            exec objs_buffer_viewhelper @buffer_operation = @buffer_operation, @obj_type = @obj_type, @base_view = @base_view, @pkey = @pkey, @join = @join, @where = @where,
                @fields = @fields out, @sql = @sql out			

            set @sql = replace(replace(replace(@sql, '{pkey}', @pkey), '{base_view}', @base_view), '{obj_type}', @obj_type)

            exec sp_executesql @sql, @fields,
                @mol_id, @today, @d_doc_from, @d_doc_to,
                @search,
                @buffer_id
        end

        else 
        begin
            -- @rowscount
            if @cacheonly = 0
            begin
                set @sql = N'select @rowscount = count(*) from {base_view} x ' + @join + @where
                set @fields = @fields_base + ', @rowscount int out'

                set @sql = replace(replace(replace(@sql, '{pkey}', @pkey), '{base_view}', @base_view), '{obj_type}', @obj_type)
                
                exec sp_executesql @sql, @fields,
                    @mol_id, @today, @d_doc_from, @d_doc_to,
                    @search,
                    @rowscount out
            end
            
            -- @order_by
            declare @order_by nvarchar(50) = N' order by x.{pkey}'

            if @sort_expression is not null
            begin
                if charindex('value_ccy', @sort_expression) = 1 begin
                    set @sort_expression = replace(@sort_expression, 'value_ccy', 'abs(value_ccy)')
                    set @sort_expression = @sort_expression + ', d_doc'
                end
                set @order_by = N' order by ' + @sort_expression
            end

            delete from sdocs_cache where mol_id = @mol_id

            declare @subquery nvarchar(max) = 
                '(select x.* from {base_view} x '
                + @join + @where
                + ' ) x ' + @order_by

            -- cache
            if isnull(@rowscount,0) < 5000 or @cacheonly = 1
            begin			
                declare @sql_cache nvarchar(max) = N'
                    insert into sdocs_cache(mol_id, doc_id)
                    select @mol_id, x.doc_id
                    from ' + @subquery
                set @fields = @fields_base

                set @sql_cache = replace(replace(replace(@sql_cache, '{pkey}', @pkey), '{base_view}', @base_view), '{obj_type}', @obj_type)
                exec sp_executesql @sql_cache, @fields,
                    @mol_id, @today, @d_doc_from, @d_doc_to,
                    @search
            end

            if @cacheonly = 0
            begin
                -- @sql
                set @sql = N'select x.* from ' + @subquery

                -- optimize on fetch
                if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

                set @fields = @fields_base + ', @offset int, @fetchrows int'

                if @trace = 1 print @sql + char(10)

                set @sql = replace(replace(replace(@sql, '{pkey}', @pkey), '{base_view}', @base_view), '{obj_type}', @obj_type)
                exec sp_executesql @sql, @fields,
                    @mol_id, @today, @d_doc_from, @d_doc_to,
                    @search,
                    @offset, @fetchrows
            end

        end -- if

    exec drop_temp_table '#subjects,#ids,#search_ids,#products'
end
go
