if object_id('invoices_pays_view') is not null drop proc invoices_pays_view
go
-- exec invoices_pays_view 1000, @folder_id = -1
create proc invoices_pays_view
	@mol_id int,
	-- filter		
	@d_from date = null,
	@d_to date = null,
	@search nvarchar(max) = null,
	@inv_condition_pay varchar(20) = null,
	@inv_condition_fund varchar(20) = null,
	@inv_condition varchar(20) = null,
	@inv_milestone varchar(50) = null,
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
    -- access
        declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
        declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
        
        declare @ids as app_pkids
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
        insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'INVPAY'

    -- cast @search
        declare @doc_id int
            
        if dbo.hashid(@search) is not null
        begin
            set @doc_id = dbo.hashid(@search)
            set @search = null
        end
        else begin
            set @search = replace('%' + @search + '%', ' ', '%')
        end

        declare @today datetime = dbo.today()

    -- prepare sql
        declare @sql nvarchar(max), @fields nvarchar(max)

    -- where
        declare @where nvarchar(max) = concat(
            N' where (1 = 1)'

            , case
                when @search is null 
                    and @folder_id is null 
                    and @inv_condition_pay is null
                    then ' and x.inv_d_plan is not null'
            end
            
            , case when @d_from is not null then ' and (x.inv_d_plan >= @d_from)' end
            , case when @d_to is not null then ' and (x.inv_d_plan <= @d_to)' end
            , case when @doc_id is not null then concat(' and exists(select 1 from supply_r_invpays where inv_id = x.inv_id and ', @doc_id, ' in (inv_id, payorder_id, findoc_id))') end

            , case when @inv_condition_pay is not null then concat(' and (x.inv_condition_pay = ''', @inv_condition_pay, ''')') end
            , case when @inv_condition_fund is not null then concat(' and (x.inv_condition_fund = ''', @inv_condition_fund, ''')') end
            , case when @inv_condition is not null then concat(' and (x.inv_condition = ''', @inv_condition, ''')') end
            , case when @inv_milestone is not null then concat(' and (x.inv_milestone = ''', @inv_milestone, ''')') end
            
            , case
                when @search is not null then 'and (x.content like @search)'
            end
            )

    -- fields
        declare @fields_base nvarchar(max) = N'
            @mol_id int,
            @search nvarchar(max),
            @d_from date,
            @d_to date,
            @ids app_pkids readonly
        '

    -- inner
        declare @inner nvarchar(max) = N''
            + case when @folder_id is null then '' else ' join @ids ids on ids.id = x.row_id ' end
            
    -- select
        if @buffer_operation is null
        begin
            -- @rowscount
            set @sql = N'select @rowscount = count(*) from v_supply_r_invpays_totals x ' + @inner + @where
            set @fields = @fields_base + ', @rowscount int out'

            exec sp_executesql @sql, @fields,
                @mol_id,
                @search, @d_from, @d_to,
                @ids,
                @rowscount out
            
            -- @order_by
            declare @order_by nvarchar(50) = N' order by x.inv_date'
            if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

            declare @subquery nvarchar(max) = N'(select x.* from v_supply_r_invpays_totals x '
                + @inner + @where
                + ' ) x ' + @order_by

            -- @sql
            set @sql = N'select x.* from ' + @subquery

            -- optimize on fetch
            if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

            set @fields = @fields_base + ', @offset int, @fetchrows int'

            if @trace = 1 print @sql + char(10)

            exec sp_executesql @sql, @fields,
                @mol_id,
                @search, @d_from, @d_to,
                @ids,
                @offset, @fetchrows
        end

    -- buffer operations
        else
        begin
            set @rowscount = -1 -- dummy

            declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

            if @buffer_operation = 1
            begin
                -- add to buffer
                set @sql = N'
                    delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''INVPAY'';
                    insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                    select @buffer_id, ''INVPAY'', x.row_id, @mol_id from v_supply_r_invpays_totals x '
                    + @inner + @where
                set @fields = @fields_base + ', @buffer_id int'

                exec sp_executesql @sql, @fields,
                    @mol_id,
                    @search, @d_from, @d_to,
                    @ids, @buffer_id
            end

            else if @buffer_operation = 2
            begin
                -- remove from buffer
                set @sql = N'
                    delete from objs_folders_details
                    where folder_id = @buffer_id
                        and obj_type = ''INVPAY''
                        and obj_id in (select row_id from v_supply_r_invpays_totals x ' + @where + ')'
                set @fields = @fields_base + ', @buffer_id int'
                
                exec sp_executesql @sql, @fields,
                    @mol_id,
                    @search, @d_from, @d_to,
                    @ids, @buffer_id
            end
        end
end
go
