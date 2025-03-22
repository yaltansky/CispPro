if object_id('mfr_wk_sheets_details_view') is not null drop proc mfr_wk_sheets_details_view
go
create proc mfr_wk_sheets_details_view
	@mol_id int,
	@filter_xml xml,
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
        declare @pkey varchar(50) = 'ID'
        declare @base_view varchar(50) = 'V_MFR_WK_SHEETS_DETAILS'
        declare @obj_type varchar(8) = 'MFWD'

    -- parse filter
		declare
			@place_id int,	
			@executor_id int,	
			@completed int,	
			@d_from date,
			@d_to date,			
			@folder_id int,
			@buffer_operation int,
			@search nvarchar(max)

		declare @handle_xml int; exec sp_xml_preparedocument @handle_xml output, @filter_xml
			select
				@place_id = nullif(place_id, 0),
				@executor_id = nullif(executor_id, 0),
				@completed = completed,
				@d_from = nullif(d_from, '1900-01-01'),
				@d_to = nullif(d_to, '1900-01-01'),				
				@folder_id = nullif(folder_id, 0),
				@buffer_operation = nullif(buffer_operation, 0),
				@search = search
			from openxml (@handle_xml, '/*', 2) with (
				PLACE_ID INT,	
				EXECUTOR_ID INT,	
				COMPLETED INT,	
				D_FROM DATE,
				D_TO DATE,
				Search VARCHAR(MAX),
				FOLDER_ID INT,
				BUFFER_OPERATION INT
				)
		exec sp_xml_removedocument @handle_xml

    -- @ids
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
        declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type

    -- @search_ids
        declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)

        if exists(select 1 from @search_ids) set @search = null
        else set @search = '%' + replace(@search, ' ', '%') + '%'		

    -- prepare sql
        declare @sql nvarchar(max), @fields nvarchar(max)

        declare @where nvarchar(max) = concat(
            ' where (1=1)'
            , case 
                when @completed = 1 then ' and (x.wk_completion_rows = 1)' 
                when @completed = 0 then ' and (x.wk_completion_rows < 1)' 
                -- when @search is null 
                --     and @folder_id is null
                --     then ' and (x.status_id between 0 and 99)'
            end		
            , case when @place_id is not null then ' and (x.place_id = @place_id)' end
            , case when @executor_id is not null then ' and (x.mol_id = @executor_id)' end
            , case when @d_from is not null then ' and (x.d_doc >= @d_from)' end
            , case when @d_to is not null then ' and (x.d_doc <= @d_to)' end
            , case
                when @search is not null then ' and (
                    x.mol_name like @search
                    or x.place_name like @search
                    or x.wk_sheet_number like @search
                    )'
            end
            )

        declare @fields_base nvarchar(max) = N'		
            @mol_id int,		
            @place_id int,
            @executor_id int,
            @completed int,
            @d_from datetime,
            @d_to datetime,
            @search nvarchar(max),
            @ids app_pkids readonly,
            @search_ids app_pkids readonly
        '

        declare @join nvarchar(max) = N'
            '
            + case when exists(select 1 from @ids) then ' join @ids i on i.id = x.[pkey] ' else '' end
            + case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.[pkey]' else '' end
            
        if @buffer_operation is  null
        begin
            -- @rowscount
            set @sql = N'select @rowscount = count(*) from [base_view] x ' + @join + @where
            set @fields = @fields_base + ', @rowscount int out'

            set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
            exec sp_executesql @sql, @fields,
                @mol_id, @place_id, @executor_id, @completed, @d_from, @d_to, @search,
                @ids, @search_ids,
                @rowscount out
        
            -- @order_by
            declare @order_by nvarchar(50) = N' order by x.[pkey]'
            if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

            declare @subquery nvarchar(max) = N'
                (
                    select x.* from [base_view] x
                '
                + @join + @where
                +' ) x ' + @order_by

            -- @sql
            set @sql = N'select x.* from ' + @subquery

            -- optimize on fetch
            if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

            set @fields = @fields_base + ', @offset int, @fetchrows int'

            set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
            
            if @trace = 1 print @sql
            
            exec sp_executesql @sql, @fields,
                @mol_id, @place_id, @executor_id, @completed, @d_from, @d_to, @search,
                @ids, @search_ids,
                @offset, @fetchrows
        end

        else begin
            declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

            set @rowscount = -1 -- dummy
            set @fields = @fields_base
                        
            exec objs_buffer_viewhelper
                @buffer_operation = @buffer_operation, @obj_type = @obj_type, @base_view = @base_view,
                @pkey = @pkey, @join = @join, @where = @where,
                @fields = @fields out, @sql = @sql out

            if @trace = 1 print @sql

            exec sp_executesql @sql, @fields,
                @mol_id, @place_id, @executor_id, @completed, @d_from, @d_to, @search,
                @ids, @search_ids,
                @buffer_id
        end -- buffer_operation
end
go

-- exec mfr_wk_sheets_details_view 1000, '<f>
-- <COMPLETED>0</COMPLETED>
-- </f>', @trace = 1
