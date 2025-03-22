if object_id('mfr_drafts_view') is not null drop proc mfr_drafts_view
go
-- exec mfr_drafts_view 1000, @doc_id = 1676397, @executor_id = 307, @trace = 1
create proc mfr_drafts_view
	@mol_id int,	
	-- filter
	@plan_id int = null,
	@doc_id int = null,
	@product_id int = null,
	@type_id int = null,
	@work_type_id int = null,
	@status_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@attr_name varchar(50) = null,
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
-- pattern params
	declare 
	    @today datetime = dbo.today(),
        @search_attr bit = 0,
        @doc_plan_id int,
        -- 
        @pkey varchar(50) = 'DRAFT_ID',
	    @base_view varchar(50) = 'V_SDOCS_MFR_DRAFTS',
	    @obj_type varchar(16) = 'MFD',
        @order_by nvarchar(50) = ' order by x.draft_id',
        @sql nvarchar(max),
        @where nvarchar(max),
        @join nvarchar(max)

    set nocount on;
	set transaction isolation level read uncommitted;

-- #ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	create table #ids(id int primary key)
	exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'
	if @folder_id is not null set @doc_id = null

-- #search_ids
	create table #search_ids(id int primary key)
	insert into #search_ids select id from dbo.hashids(@search)
	
	set @search = replace(replace(@search, '[', ''), ']', '')

	if substring(@search, 1, 1) = ':' begin
		set @search_attr = 1
		set @search = substring(@search, 2, 255)
	end		

	if exists(select 1 from #search_ids) set @search = null
	else set @search = '%' + replace(@search, ' ', '%') + '%'		

-- #plans
	create table #plans(id int primary key)
	
    if @doc_id is not null or @folder_id is not null
		set @plan_id = null
	else if @plan_id = 0
		insert into #plans select plan_id from mfr_plans where status_id = 1
	else if @plan_id is not null
		insert into #plans select @plan_id

-- @attrs
	declare @attrs as app_pkids
	if @attr_name is not null insert into @attrs select attr_id from mfr_attrs 	where group_name = @attr_name or name = @attr_name

-- prepare sql
	set @doc_plan_id = (select plan_id from sdocs where doc_id = @doc_id);

	set @where = concat(
		' where (1=1)'

		, case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end

        , case when @work_type_id is not null
            then concat(
                ' and (',
                    case
                        when @doc_id is not null then
                            case 
                                when @work_type_id = 1 then 'x.work_type_1 = 1 or '
                                when @work_type_id = 2 then 'x.work_type_2 = 1 or '
                                when @work_type_id = 3 then 'x.work_type_3 = 1 or '
                            end
                    end,
                    'exists(select 1 from mfr_drafts_opers where draft_id = x.draft_id and work_type_id = ', @work_type_id, ') ',
                ')'
            )
          end

		, case 
            when @plan_id = 0 then ' and (x.mfr_doc_id in (select doc_id from sdocs where plan_id in (select id from #plans)))'
            when @plan_id is not null then concat(' and (x.plan_id = ', @plan_id, ')') 
		  end
		
        , case when @doc_id is not null then concat(' and (x.mfr_doc_id = ', @doc_id, ')') end
        , case when @product_id is not null then concat(' and (x.product_id = ', @product_id, ')') end

		, case 
            when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')')
            when @folder_id is not null then '' -- all statuses
            else ' and (x.status_id != -1)'
		  end

		, case when @d_from is not null then ' and (x.d_doc >= @d_from)' end
		, case when @d_to is not null then ' and (x.d_doc <= @d_to)' end

		, case when @attr_name is not null and isnull(@extra_id,0) != -3 then ' and exists(
			select 1 from sdocs_mfr_drafts_attrs where [pkey] = x.[pkey] and attr_id in (select id from @attrs)
			)' end
		
		, case when @executor_id is not null then concat(' and (isnull(x.executor_id, x.add_mol_id) = ', @executor_id, ')') end
		
		, case
			when @search is not null then 
				case
					when @search_attr = 1 then ' and (
						exists(select 1 from sdocs_mfr_drafts_attrs where [pkey] = x.[pkey] and note like @search)
					)'
					else ' and (
						x.item_name like @search
						or x.number like @search
						or x.mfr_number like @search
						or x.note like @search
						or exists(select 1 from sdocs_mfr_drafts_attrs where [pkey] = x.[pkey] and note like @search)
					)'
				end			
		  end
		, case
			-- Есть дублирование операций
			when @extra_id = 1 then ' and exists(
				select 1 from mfr_drafts_opers o
					join mfr_drafts d on d.draft_id = o.draft_id
				where o.draft_id = x.draft_id and isnull(o.is_deleted,0) = 0
					and d.mfr_doc_id > 0
				group by o.draft_id, o.number
				having count(*) > 1
				)
				'
			-- Нет оборудования
            when @extra_id = 2 then ' and not exists(
                select 1
                from mfr_drafts_opers o
                where o.work_type_id = 1
                    and o.draft_id = x.draft_id
                    and not exists(
                        select 1
                        from mfr_drafts_opers_resources
                        where oper_id = o.oper_id
                        )
                )'
			-- Нет стоимости кооперации
            when @extra_id = 3 then ' and exists(
                select 1
                from mfr_drafts_opers o
                where o.work_type_id = 3
                    and o.draft_id = x.draft_id
                    and not exists(
                        select 1
                        from mfr_drafts_opers_resources
                        where oper_id = o.oper_id
                            and loading_value > 0
                        )
                )'
			-- ДСЕ: варианты исполнения
			when @extra_id = 10 then ' and exists(select 1 from mfr_pdms where item_id = x.item_id and is_default = 0 and is_deleted = 0)'
			-- ДСЕ: варианты маршруто
			when @extra_id = 13 then ' and exists(select 1 from mfr_pdm_opers where pdm_id = x.pdm_id having count(distinct variant_number) > 1)'
			-- ДСЕ: опции
			when @extra_id = 11 then ' and exists(select 1 from mfr_pdm_options where pdm_id = x.pdm_id and is_deleted = 0)'
			-- ДСЕ: аналоги
			when @extra_id = 12 then ' and exists(select 1 from mfr_pdm_items where pdm_id = x.pdm_id and parent_id is not null)'
			-- Несоответствия признака "Производим"
			when @extra_id = 14 then ' and x.is_buy = 0 and exists(select 1 from mfr_drafts_opers where draft_id = x.draft_id and work_type_id != 1 and is_deleted = 0)'
			-- Несоответствия признака "Покупаем"
			when @extra_id = 15 then ' and x.is_buy = 1 and exists(select 1 from mfr_drafts_opers where draft_id = x.draft_id and work_type_id != 2 and is_deleted = 0)'
		  end
		);
			
	declare @fields nvarchar(max);
    declare @fields_base nvarchar(max) = '
		@mol_id int,				
		@d_from datetime,
		@d_to datetime,
		@search nvarchar(max),		
		@attrs app_pkids readonly,
		@today datetime
	    ';

	set @join = ''
		+ case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.[pkey] ' else '' end
		+ case when exists(select 1 from #search_ids) then 'join #search_ids i2 on i2.id = x.[pkey]' else '' end
        ;
		
	if @buffer_operation is null
	begin
		-- @rowscount
			set @sql = N'select @rowscount = count(*) from [base_view] x ' + @join + @where
			set @fields = @fields_base + ', @rowscount int out'

			set @sql = replace(replace(replace(@sql, '[pkey]', @pkey), '[base_view]', @base_view), '[obj_type]', @obj_type)

			exec sp_executesql @sql, @fields,
				@mol_id, @d_from, @d_to, @search,
				@attrs, @today,
				@rowscount out
	
		-- @order_by
            if @doc_id is not null set @order_by = ' order by x.is_root desc, x.item_name';
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
            @mol_id, @d_from, @d_to, @search,
            @attrs, @today,
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
			@mol_id, @d_from, @d_to, @search,
			@attrs, @today,
			@buffer_id
	
	end -- buffer_operation

	exec drop_temp_table '#plans,#ids,#search_ids'
end
go
