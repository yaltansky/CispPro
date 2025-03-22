if object_id('mfr_pdms_view') is not null drop proc mfr_pdms_view
go
-- exec mfr_pdms_view 1000
create proc mfr_pdms_view
	@mol_id int,	
	-- filter
	@plan_id int = null,
	@doc_id int = null,
	@type_id int = null,
	@status_id int = null,
	@d1_from date = null,
	@d1_to date = null,
	@d2_from date = null,
	@d2_to date = null,
	@exec_reglament_id int = null,
	@executor_id int = null,
	@extra_id int = null,
	@folder_id int = null,
	@buffer_operation int = null,
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
	@search nvarchar(max) = null,
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

	declare @today date = dbo.today()

-- pattern params
	declare @pkey varchar(50) = 'PDM_ID'
	declare @base_view varchar(50) = 'V_MFR_PDMS'
	declare @obj_type varchar(16) = 'MFPDM'

-- #ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	create table #ids(id int primary key)
	exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'
	if @folder_id is not null set @doc_id = null

-- #search_ids
	create table #search_ids(id int primary key)
	insert into #search_ids select id from dbo.hashids(@search)
	
	declare @search_attr bit = 0

	set @search = replace(replace(@search, '[', ''), ']', '')

	if substring(@search, 1, 1) = ':' begin
		set @search_attr = 1
		set @search = substring(@search, 2, 255)
	end		

	if exists(select 1 from #search_ids) set @search = null
	else set @search = '%' + replace(@search, ' ', '%') + '%'		

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)
	declare @doc_plan_id int = (select plan_id from sdocs where doc_id = @doc_id)

	declare @where nvarchar(max) = concat(
		' where (1=1)'
		, case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end
		, case 
				when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')')
				when @folder_id is not null then '' -- all statuses
				else ' and (x.status_id != -1)'
		  end

        -- d_doc
		, case when @d1_from is not null then ' and (x.d_doc >= @d1_from)' end
		, case when @d1_to is not null then ' and (x.d_doc <= @d1_to)' end
		
        -- update_date
        , case when @d2_from is not null then ' and (x.update_date >= @d2_from)' end
		, case when @d2_to is not null then ' and (cast(x.update_date as date) <= @d2_to)' end

		, case when @exec_reglament_id is not null then concat(' and (x.exec_reglament_id = ', @exec_reglament_id, ')') end
		, case when @executor_id is not null then 
            concat(' and ', @executor_id, ' in (x.executor_id, x.add_mol_id, x.update_mol_id)') end
		, case when @search is not null then ' and (x.item_name like @search)' end
		)
			
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,				
		@d1_from date,
		@d1_to date,
		@d2_from date,
		@d2_to date,
		@search nvarchar(max),		
		@today date
	'

	declare @join nvarchar(max) = N''
		+ case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.[pkey] ' else '' end
		+ case when exists(select 1 from #search_ids) then 'join #search_ids i2 on i2.id = x.[pkey]' else '' end
		
	DECLARE @hint VARCHAR(50) = ' OPTION (RECOMPILE, OPTIMIZE FOR UNKNOWN)'

	if @buffer_operation is null
	begin
		-- @rowscount
			set @sql = N'select @rowscount = count(*) from [base_view] x ' + @join + @where
			set @fields = @fields_base + ', @rowscount int out'

			set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
			set @sql = @sql + @hint

			if @trace = 1 print 'count: ' + @sql

			exec sp_executesql @sql, @fields,
				@mol_id, @d1_from, @d1_to, @d2_from, @d2_to, @search, @today,
				@rowscount out
	
		-- @order_by
			declare @order_by nvarchar(50) = N' order by x.pdm_id'
			if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			declare @subquery nvarchar(max) = N'(select x.* from [base_view] X '
				+ @join + @where
				+ ') x ' + @order_by

        -- @sql
        	set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        	if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'
	        set @fields = @fields_base + ', @offset int, @fetchrows int'
		
        set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)
		if @trace = 1 print 'select: ' + @sql

		exec sp_executesql @sql, @fields,
            @mol_id, @d1_from, @d1_to, @d2_from, @d2_to, @search, @today,
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

		print @fields

		exec sp_executesql @sql, @fields,
			@mol_id, @d1_from, @d1_to, @d2_from, @d2_to, @search, @today,
			@buffer_id
	
	end -- buffer_operation

	exec drop_temp_table '#ids,#search_ids'
end
go
