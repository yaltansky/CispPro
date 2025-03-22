if object_id('mfr_wk_sheets_view') is not null drop proc mfr_wk_sheets_view
go
-- exec mfr_wk_sheets_view 700
create proc mfr_wk_sheets_view
	@mol_id int,	
	-- filter
	@place_id int = null,
	@status_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@search nvarchar(max) = null,
	@folder_id int = null,
	@buffer_operation int = null, 
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
        declare @pkey varchar(50) = 'WK_SHEET_ID'
        declare @base_view varchar(50) = 'V_MFR_WK_SHEETS'
        declare @obj_type varchar(3) = 'MFW'

    -- @subjects
        declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
        declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

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
                when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
                when @search is null 
                    and @folder_id is null
                    then ' and (x.status_id not in (-1,100))'
            end		
            , case when @place_id is not null then ' and (x.place_id = @place_id)' end
            , case when @d_from is not null then ' and (x.d_doc >= @d_from)' end
            , case when @d_to is not null then ' and (x.d_doc <= @d_to)' end
            , case
                when @search is not null then ' and (
                    x.number like @search
                    or x.place_name like @search
                    or x.note like @search
                    or exists(
                        select 1 from mfr_wk_sheets_details wd
                            join mols on mols.mol_id = wd.mol_id
                        where wk_sheet_id = x.wk_sheet_id and mols.name like @search
                        )
                    )'
            end
            )

        declare @today datetime = dbo.today()
        declare @fields_base nvarchar(max) = N'		
            @mol_id int,		
            @d_from datetime,
            @d_to datetime,
            @today datetime,
            @place_id int,
            @search nvarchar(max),
            @ids app_pkids readonly,
            @search_ids app_pkids readonly,
            @subjects app_pkids readonly
        '

        declare @join nvarchar(max) = N'
            join @subjects s on s.id = x.subject_id
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
                @mol_id, @d_from, @d_to, @today, @place_id, @search,
                @ids, @search_ids, @subjects,
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
                @mol_id, @d_from, @d_to, @today, @place_id, @search,
                @ids, @search_ids, @subjects,
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

            exec sp_executesql @sql, @fields,
                @mol_id, @d_from, @d_to, @today, @place_id, @search,
                @ids, @search_ids, @subjects,
                @buffer_id
        end -- buffer_operation
end
go
