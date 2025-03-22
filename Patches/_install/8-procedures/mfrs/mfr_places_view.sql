if object_id('mfr_places_view') is not null drop proc mfr_places_view
go
-- exec mfr_places_view 700
-- @@STANDARD VIEW
create proc mfr_places_view
	@mol_id int,	
	-- filter
	@subject_id int = null,
	@status_mode int = null,
	@dispatcher_id int = null,
	@search nvarchar(max) = null,
	--folder/buffer
	@folder_id int = null,
	@buffer_operation int = null,
		-- 1 add rows to buffer
		-- 2 remove rows from buffer	
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	--
	@rowscount int = null out
as
begin

    set nocount on;
	set transaction isolation level read uncommitted;

-- pattern params
	declare @pkey varchar(50) = 'PLACE_ID'
	declare @base_view varchar(50) = 'V_MFR_PLACES'
	declare @obj_type varchar(3) = 'MFL'

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

		, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end

		, case when @dispatcher_id is not null then concat(' and x.place_id in (select place_id from mfr_places_mols where mol_id = ', @dispatcher_id, ')') end

		, case 
			when @status_mode is not null then 
				case 
					when @status_mode = 1 then ' and (x.is_deleted = 0)' 
					when @status_mode = -1 then ' and (x.is_deleted = 1)'
				end
			when @folder_id is not null then '' -- all statuses
			else ' and (x.is_deleted = 0)'
		  end

		, case
			when @search is not null then 
				' and (x.name like @search or x.note like @search)'
		  end
		)
			
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,				
		@search nvarchar(max),		
		@ids app_pkids readonly,
		@search_ids app_pkids readonly,
		@subjects app_pkids readonly
	'

	declare @join nvarchar(max) = N''
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.[pkey] ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.[pkey]' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from [base_view] x ' + @join + @where
        set @fields = @fields_base + ', @rowscount int out'

		set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
        exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids, @subjects,
            @rowscount out
	
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.[pkey]'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'(select x.* from [base_view] X '
            + @join + @where
            + ') x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

		-- print @sql

        set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
		exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids, @subjects,
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

		exec sp_executesql @sql, @fields,
			@mol_id, @search,
			@ids, @search_ids, @subjects,
			@buffer_id

	end -- buffer_operation

end
go
