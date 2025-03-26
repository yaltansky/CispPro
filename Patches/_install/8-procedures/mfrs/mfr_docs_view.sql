if object_id('mfr_docs_view') is not null drop proc mfr_docs_view
go
-- exec mfr_docs_view 1000, @filter_xml='<f></f>', @trace = 1
create proc mfr_docs_view
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

    -- parse filter
		declare
			@acc_register_id int,
			@subject_id int,
			@plan_id int,	
			@type_id int,
			@status_id int,	
			@ext_status_id int,	
			@agent_id int,	
			@product_id int,
			@product_group1_id int,
			@d_doc_from date,
			@d_doc_to date,			
			@folder_id int,
			@buffer_operation int,
			@search nvarchar(max),
			@part_parent_id int,
			@dates_id int,
			@extra_id int

		declare @handle_xml int; exec sp_xml_preparedocument @handle_xml output, @filter_xml
			select
				@acc_register_id = nullif(acc_register_id, 0),				
				@subject_id = nullif(subject_id, 0),
				@plan_id = nullif(plan_id, 0),
				@type_id = nullif(type_id, 0),				
				@status_id = nullif(status_id, 0),
				@ext_status_id = nullif(ext_status_id, 0),
				@agent_id = nullif(agent_id, 0),
				@product_id = nullif(product_id, 0),
				@product_group1_id = nullif(product_group1_id, 0),
				@d_doc_from = nullif(d_doc_from, '1900-01-01'),
				@d_doc_to = nullif(d_doc_to, '1900-01-01'),				
				@part_parent_id = nullif(part_parent_id, 0),
				@folder_id = nullif(folder_id, 0),
				@buffer_operation = nullif(buffer_operation, 0),
				@search = search,
				@dates_id = nullif(DatesId, 0),
				@extra_id = nullif(ExtraId, 0)
			from openxml (@handle_xml, '/*', 2) with (
				ACC_REGISTER_ID INT,
				SUBJECT_ID INT,
				PLAN_ID INT,	
				TYPE_ID INT,	
				STATUS_ID INT,	
				EXT_STATUS_ID INT,	
				AGENT_ID INT,
				PRODUCT_ID INT,
				PRODUCT_GROUP1_ID INT,
				D_DOC_FROM DATE,
				D_DOC_TO DATE,
				PART_PARENT_ID INT,
				Search VARCHAR(MAX),
				DatesId INT,
				ExtraId INT,
				FOLDER_ID INT,
				BUFFER_OPERATION INT
				)
		exec sp_xml_removedocument @handle_xml

	if (@offset = 0 or @buffer_operation is not null)
		or not exists(select 1 from sdocs_cache with(nolock) where mol_id = @mol_id)
	begin
	-- select, then cache results		
		exec mfr_docs_view;10
			@mol_id = @mol_id,			
			@acc_register_id = @acc_register_id,
			@subject_id = @subject_id,
			@plan_id = @plan_id,
			@type_id = @type_id,			
			@status_id = @status_id,
			@ext_status_id = @ext_status_id,
			@agent_id = @agent_id,
			@product_id = @product_id,
			@product_group1_id = @product_group1_id,
			@part_parent_id = @part_parent_id,
			@d_doc_from = @d_doc_from,
			@d_doc_to = @d_doc_to,
			@dates_id = @dates_id,
			@folder_id = @folder_id,
			@buffer_operation = @buffer_operation,
			@search = @search,
			@extra_id = @extra_id,
			@sort_expression = @sort_expression,
			@offset = @offset,
			@fetchrows = @fetchrows,			
			@rowscount = @rowscount out,
			@trace = @trace
	end

	-- use cache
	else begin
		select x.*
		from v_mfr_sdocs x
			join sdocs_cache xx with(nolock) on xx.mol_id = @mol_id and xx.doc_id = x.doc_id
		order by xx.id
		offset @offset rows fetch next @fetchrows rows only

		set @rowscount = (select count(*) from sdocs_cache where mol_id = @mol_id)
	end
end
go
create proc mfr_docs_view;10
	@mol_id int,
	-- filter	
	@acc_register_id int = null,
	@subject_id int = null,
	@plan_id int = null,	
	@type_id int = null,	
	@status_id int = null,	
	@ext_status_id int = null,	
	@agent_id int = null,
	@product_id int = null,
	@product_group1_id int = null,
	@part_parent_id int = null,
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@dates_id int = null,
	@folder_id int = null,
	@buffer_operation int = null,
	@search nvarchar(max) = null,
	@extra_id int = null,
	@sort_expression varchar(50) = null,	
	@offset int = 0,
	@fetchrows int = 30,	
	@cacheonly bit = 0,
	--
	@rowscount int out,
	@trace bit = 0
as
begin

	-- pattern params
		declare @pkey varchar(50) = 'DOC_ID'
		declare @base_view varchar(50) = 'V_MFR_SDOCS'
		declare @obj_type varchar(16) = 'MFR'
		declare @today datetime = dbo.today()

	-- access
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'SBJ'
		
		create table #ids(id int primary key)
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'

	-- #search_ids
		create table #search_ids(id int primary key); insert into #search_ids select distinct id from dbo.hashids(@search)

        -- #numbers
            create table #numbers(number varchar(50) primary key)
            insert into #numbers select distinct item from dbo.str2rows(@search, ' ') where isnull(item, '') != ''
            if exists(select 1 from #numbers) and exists(select 1 from mfr_sdocs where number = (select top 1 number from #numbers))
                insert into #search_ids select doc_id from mfr_sdocs
                where number in (select number from #numbers)

		if exists(select 1 from #search_ids) begin
			set @search = null
			set @status_id = null
		end
		else set @search = '%' + replace(@search, ' ', '%') + '%'

		if not exists(select 1 from #search_ids) and @search is not null
		begin
			insert into #search_ids select doc_id from mfr_sdocs where number like @search
                and status_id != -1
			if exists(select 1 from #search_ids) set @search = null
		end

		declare @month_from datetime = dateadd(d, -datepart(d, @today)+1, @today)
		declare @month_to datetime = dateadd(m, 1, @month_from) - 1

	-- #products
		create table #products(id int primary key)
		if @search is not null and len(@search) > 4
			insert into #products select product_id from products where name like @search
        
        if @product_group1_id is not null begin
            delete from #products
            insert into #products select product_id from mfr_products_grp1
            where attr_id = @product_group1_id and product_id is not null
        end
		
        if exists(select 1 from #products) set @search = null

	-- @extra_id
		if @extra_id = 10 set @plan_id = null

	-- prepare sql
		declare @sql nvarchar(max), @fields nvarchar(max)

		declare @where nvarchar(max) = concat(
			' where (
				x.subject_id in (select id from #subjects)
				or x.doc_id in (select doc_id from sdocs_mols with(nolock) where mol_id = @mol_id and a_read = 1)
				)
				'
			
            , case 
                when @extra_id = 100 then ' and (x.ext_type_id = 1)'
                when not exists(select 1 from #ids) then ' and (x.ext_type_id is null)'
              end

			, case when @acc_register_id is not null then concat(' and (x.acc_register_id = ', @acc_register_id, ')') end
			, case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end
			, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
			, case when @agent_id is not null then concat(' and (x.agent_id = ', @agent_id, ')') end
			
			, case
                when @plan_id = 0 and not exists(select 1 from #search_ids) then ' and (x.plan_id in (select plan_id from mfr_plans where status_id = 1))'
                when @plan_id is not null then concat(' and (x.plan_id = ', @plan_id, ')')
              end

			, case 
                when @status_id = 100 then concat(' and (x.status_id = ', @status_id, ')') 
                when @status_id = -1000 then ''
                when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
                when @search is null 
                        and @folder_id is null
                        and @plan_id is null
                        and not exists(select 1 from #search_ids)
                    then ' and (x.plan_status_id = 1 or x.plan_id is null) and (x.status_id != -1)'
			  end

			, case 
                when @ext_status_id is not null then concat(' and (x.ext_status_id = ', @ext_status_id, ')') 
			  end
			
			, case when @product_id is not null then concat(' and exists(select 1 from sdocs_products where doc_id = x.doc_id 
				    and product_id = ', @product_id, ')') end

			, case when @d_doc_from is not null or @d_doc_to is not null then 
			    case
					when isnull(@dates_id,0) = 1 then ' and (x.d_doc between isnull(@d_doc_from,x.d_doc) and isnull(@d_doc_to,x.d_doc))'
					when @dates_id = 2 then ' and (x.d_delivery between isnull(@d_doc_from,x.d_delivery) and isnull(@d_doc_to,x.d_delivery))'
					when @dates_id = 3 then ' and (x.d_issue_plan between isnull(@d_doc_from,x.d_issue_plan) and isnull(@d_doc_to,x.d_issue_plan))'
					when @dates_id = 4 then ' and (x.d_issue_forecast between isnull(@d_doc_from,x.d_issue_forecast) and isnull(@d_doc_to,x.d_issue_forecast))'
					when @dates_id = 5 then ' and (x.d_issue between isnull(@d_doc_from,x.d_issue) and isnull(@d_doc_to,x.d_issue))'
					when @dates_id = 6 then
						' and exists(
								select 1 from sdocs_mfr_milestones with(nolock)
								where doc_id = x.doc_id and d_to between isnull(@d_doc_from,x.d_to) and isnull(@d_doc_to,x.d_to)
									and ratio_value > 0
								)
						' 
				end
			  end
			
			, case when @part_parent_id is not null then concat(' and (x.part_parent_id = ', @part_parent_id, ')') end

			-- черновики
			, case when @extra_id = 20 then ' and (x.status_id = 0)' end
			-- отставание по срокам
			, case when @extra_id = 1 then ' and (x.d_delivery < x.d_issue_calc)' end
			-- отставание (переделы)
			, case when @extra_id = 2 then ' and exists(select 1 from sdocs_mfr_milestones with(nolock) where doc_id = x.doc_id and x.status_id != 100 and d_to < @today and progress < 1)' end
			-- текущий план (переделы)
			, case when @extra_id = 3 then ' and exists(
					select 1 from sdocs_mfr_milestones ms with(nolock)
						join mfr_sdocs sd with(nolock) on sd.doc_id = ms.doc_id and sd.plan_status_id = 1
					where ms.doc_id = x.doc_id
						and coalesce(ms.d_to_fact, ms.d_to_plan, ms.d_to_predict, ms.d_to) <= @month_to
					)'
				end
			-- мастер-шаблоны
			, case when @extra_id = 4 then ' and (x.template_name is not null)' end
			-- Требуется синхронизация
			, case when @extra_id = 5 then ' and (x.sync_dirty = 1)' end
			-- Отсутствует в планах
			, case when @extra_id = 10 then ' and (x.plan_id is null)' end

			-- @search
			, case
					when @search is not null then 'and (x.content like @search)'
					when exists(select 1 from #products) then '
						and exists(
							select 1 from sdocs_products sp with(nolock)
								join #products p on p.id = sp.product_id
							where doc_id = x.doc_id
							)
						'
				end
			)

		declare @fields_base nvarchar(max) = N'
			@mol_id int,
			@today datetime,
			@month_from datetime,
			@month_to datetime,
			@d_doc_from datetime,
			@d_doc_to datetime,			
			@search nvarchar(max)
			'

		declare @join nvarchar(max) = N''
			+ case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.doc_id ' else '' end
			+ case when exists(select 1 from #search_ids) then 'join #search_ids i2 on i2.id = x.doc_id' else '' end

		DECLARE @hint VARCHAR(50) = ' OPTION (RECOMPILE, OPTIMIZE FOR UNKNOWN)'

		if @buffer_operation is not null
		begin
			declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

			set @rowscount = -1 -- dummy
			set @fields = @fields_base
						
			exec objs_buffer_viewhelper
				@buffer_operation = @buffer_operation, @obj_type = @obj_type, @base_view = @base_view, @pkey = @pkey, @join = @join, @where = @where,
				@fields = @fields out, @sql = @sql out			

			exec sp_executesql @sql, @fields,
				@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to, 
				@search,
				@buffer_id
		end

		else 
		begin

			-- @rowscount
			if @cacheonly = 0
			begin
				set @sql = N'select @rowscount = count(*) from V_MFR_SDOCS x with(nolock) ' + @join + @where
				set @sql = @sql + @hint

				set @fields = @fields_base + ', @rowscount int out'

				exec sp_executesql @sql, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to, 
					@search,
					@rowscount out
			end

			-- @order_by
			declare @order_by nvarchar(100) = N' order by x.priority_sort'
			
			if @sort_expression is not null
			begin
				if charindex('value_ccy', @sort_expression) = 1 begin
					set @sort_expression = replace(@sort_expression, 'value_ccy', 'abs(value_ccy)')
					set @sort_expression = @sort_expression + ', d_doc'
				end
				set @order_by = N' order by ' + @sort_expression
			end

			delete from sdocs_cache where mol_id = @mol_id

			declare @subquery nvarchar(max) = N'(select x.* from V_MFR_SDOCS x with(nolock) '
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

				exec sp_executesql @sql_cache, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to, 
					@search
			end

			if @cacheonly = 0
			begin
				-- @sql
				set @sql = N'select x.* from ' + @subquery
				-- optimize on fetch
				if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'
				-- add hint
				set @sql = @sql + @hint

				set @fields = @fields_base + ', @offset int, @fetchrows int'

				if @trace = 1 print char(10) + @sql + char(10)

				exec sp_executesql @sql, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to, 
					@search,
					@offset, @fetchrows

			end
		end -- if
	
	exec drop_temp_table '#subjects,#ids,#search_ids,#products'
end
go
