if object_id('sdocs_view') is not null drop proc sdocs_view
go
-- exec sdocs_view 1000
create proc sdocs_view
	@mol_id int,
	-- filter		
	@acc_register_id int = null,
	@subject_id int = null,
	@type_id int = null,	
	@d_doc_from date = null,
	@d_doc_to date = null,
	@stock_id int = null,	
	@status_id int = null,	
	@author_id int = null,
	@agent_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, -- 1 add rows to buffer, 2 remove rows from buffer
	@search nvarchar(max) = null,
	@extra_id int = null,
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

    -- view access
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'SBJ'
    -- #ids
        create table #ids(id int primary key)
            if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
            insert into #ids select obj_id from objs_folders_details
            where folder_id = @folder_id and obj_type in ('sd', 'mftrf', 'inv')

            if not exists(select 1 from #ids)
            begin
                insert into #ids select distinct id from dbo.hashids(@search)
                if exists(select 1 from #ids) set @search = null
            end

    set @search = '%' + replace(@search, ' ', '%') + '%'

	-- products
        create table #search_ids(id int primary key)
        if @search is not null
            and exists(
                select 1 from sdocs_products sp
                    join sdocs sd on sd.doc_id = sp.doc_id
                where product_id in (select product_id from products where name like @search)
                    and sd.status_id >= 0
                    and sd.type_id = @type_id
                )
        begin
            insert into #search_ids
            select distinct sd.doc_id from sdocs_products sp
                join sdocs sd on sd.doc_id = sp.doc_id
            where product_id in (select product_id from products where name like @search)
                and sd.status_id >= 0
                and sd.type_id = @type_id
            
            set @search = null
        end

    -- prepare sql
        declare @sql nvarchar(max), @fields nvarchar(max)

        declare @where nvarchar(max) = concat(
            N' where (1 = 1) '
            
            , case when @acc_register_id is not null then concat(' and (x.acc_register_id = ', @acc_register_id, ')') end
            , case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
            , case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end
            , case when @stock_id is not null then ' and (x.stock_id = @stock_id)' end

            , case 
                when @status_id = -2 then concat(' and (x.status_id = 0 and x.add_mol_id = ', @mol_id, ')')
                when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
                when @folder_id is null and @search is null then ' and (x.status_id <> -1)'
              end

            , case when @d_doc_from is not null then ' and (x.d_doc >= @d_doc_from)' end		
            , case when @d_doc_to is not null then ' and (x.d_doc <= @d_doc_to)' end
            , case when @author_id is not null then concat(' and (x.add_mol_id = ', @author_id, ')') end
            , case when @search is not null then 'and (x.content like @search)' end
            )

	declare @fields_base nvarchar(max) = N'		
		@d_doc_from date,
		@d_doc_to date,
		@stock_id int,
		@search nvarchar(200),
		@extra_id int
	    '

	declare @inner nvarchar(max) = N'
		join #subjects sx on sx.id = isnull(x.subject_id,0)
		'
		+ case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids ids on ids.id = x.doc_id ' else '' end
		+ case when exists(select 1 from #search_ids) then ' join #search_ids i2 on i2.id = x.doc_id ' else '' end
		
	if @buffer_operation is not null
	begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''SD'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''SD'', x.doc_id, @mol_id from sdocs x '
				+ @inner + @where
			set @fields = @fields_base + ', @buffer_id int, @mol_id int'

			exec sp_executesql @sql, @fields,
				@d_doc_from, @d_doc_to, @stock_id,
				@search, @extra_id,
				@buffer_id, @mol_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''SD''
					and obj_id in (select doc_id from sdocs x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@d_doc_from, @d_doc_to, @stock_id,
				@search, @extra_id,
				@buffer_id
		end
	end

	else begin
        declare @hint varchar(50) = '' -- ' OPTION (RECOMPILE, OPTIMIZE FOR UNKNOWN)'
		
        -- @rowscount
			set @sql = N'select @rowscount = count(*) from v_sdocs x ' + @inner + @where
			set @sql = @sql + @hint

			set @fields = @fields_base + ', @rowscount int out'

			exec sp_executesql @sql, @fields,
				@d_doc_from, @d_doc_to, @stock_id,
				@search, @extra_id,
				@rowscount out
		
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

        -- select
            declare @subquery nvarchar(max) = N'(
                select x.* from v_sdocs x with(nolock) '
            + @inner + @where
            +' ) x ' + @order_by

        -- @sql
            set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
            if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

        if @trace = 1 print @sql

        exec sp_executesql @sql, @fields,
            @d_doc_from, @d_doc_to, @stock_id, 
            @search, @extra_id,
            @offset, @fetchrows
	end -- if

	exec drop_temp_table '#subjects,#ids,#search_ids'
end
go
