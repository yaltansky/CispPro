if object_id('mfr_plan_qjobs_view') is not null drop proc mfr_plan_qjobs_view
go
-- exec mfr_plan_qjobs_view 1000, @folder_id = -1
create proc mfr_plan_qjobs_view
	@mol_id int,	
	-- filter
	@flow_id int = null,
	@dispatcher_id int = null,
	@status_id int = null,
	@place_id int = null,
	@executor_id int = null,
	@resource_id int = null,
	@oper_name varchar(100) = null,
	@d_doc_from date = null,
	@d_doc_to date = null,
	@search nvarchar(max) = null,
	@searchPost nvarchar(max) = null,
	@filter_attrs bit = null,
	@extra_id int = null,
		-- 100 - totals
	@folder_id int = null,
	@buffer_operation int = null, 
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
		-- 99 build distinct PRODUCT_ID in buffer
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

    declare @today datetime = dbo.today()
	
    -- pattern params
		declare @pkey varchar(50) = 'ID'
		declare @base_view varchar(50) = 'V_MFR_PLANS_QJOBS2'
		declare @obj_type varchar(3) = 'MCO'

	-- totals
		if @extra_id = 100
		begin
			set @rowscount = 1
					
			select
				PLAN_Q = SUM(PLAN_Q),
				FACT_Q = SUM(FACT_Q),
				NORM_HOURS = SUM(NORM_HOURS),
				PLAN_HOURS = SUM(PLAN_HOURS),
				FACT_HOURS = SUM(FACT_HOURS),
				QUEUE_HOURS = SUM(QUEUE_HOURS)
			from mfr_plans_jobs_queues x
				join dbo.objs_buffer(@mol_id, @obj_type) i on i.id = x.detail_id

			return
		end

	-- #subjects
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'SBJ'

	-- #search_ids
		create table #search_ids(id int primary key)
		insert into #search_ids select id from dbo.hashids(@search)
		if exists(select 1 from #search_ids) set @search = null

	-- #ids
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		create table #ids(id int primary key)
		exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'

	set @search = '%' + replace(@search, ' ', '%') + '%'

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	-- @filter_attrs
		declare @productsQueryTable sysname
		if @filter_attrs = 1 exec products_builder;2 @mol_id, @productsQueryTable out

	-- @searchPost
		set @searchPost = '%' + replace(@searchPost, ' ', '%') + '%'
		create table #post_ids(id int primary key)
		insert into #post_ids
		select x.detail_id from mfr_plans_jobs_queues x
			join mfr_drafts_opers o on o.draft_id = x.draft_id and o.number = x.oper_number
				join mfr_drafts_opers_executors e on e.oper_id = o.oper_id
					join mols_posts mp on mp.post_id = e.post_id
		where mp.name like @searchPost

	-- prepare sql
		declare @sql nvarchar(max), @fields nvarchar(max)

		declare @where nvarchar(max) = concat(
			' where (1=1)'
			
			, case when @flow_id is not null then concat(' and (x.flow_id = ', @flow_id, ')') end

			, case when @dispatcher_id is not null then 
				concat(' and ', @dispatcher_id, ' in (x.moderator_id, x.executor_id)') 
				end
			
			, case when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') end
			, case when @place_id is not null then concat(' and (x.place_id = ', @place_id, ')') end
			
			, case when @executor_id is not null then 
				concat(' and exists(select 1 from mfr_plans_jobs_executors where detail_id = x.id and mol_id = ', @executor_id, ')')
				end

			, case when @resource_id is not null then concat('and (x.resource_id = ', @resource_id, ')') end
			
			, case when @d_doc_from is not null or @d_doc_to is not null then '
					and exists(
							select 1 from mfr_plans_jobs_executors e
								join mols on mols.mol_id = e.mol_id
							where e.detail_id = x.id 
								and d_doc between isnull(@d_doc_from, d_doc) and isnull(@d_doc_to, d_doc)
						)
					' 
			  end

			, case
				when @oper_name is not null then concat(' and (x.oper_name like ''%', @oper_name, ''')')
			  end

			, case
				when @search is not null then ' and (
					concat(x.place_name,
					    x.mfr_number,
					    x.job_number,
					    x.product_name,
					    x.item_name,
					    x.oper_name,
					    x.resource_name
                        ) like @search
					-- исполнители
					or exists(
						select 1 from mfr_plans_jobs_executors e
							join mols on mols.mol_id = e.mol_id
						where e.detail_id = x.id
							and mols.name like @search
						)
					-- материалы
					or exists(
						select 1
						from sdocs_mfr_drafts_items i
							join products p on p.product_id = i.item_id
						where draft_id = x.draft_id
							and i.is_buy = 1
							and p.name like @search
						)
					)'
				end
			
			, case
				-- id: 1, name: 'Нет работников'
				when @extra_id = 1 then ' and (x.count_executors = 0)'
				-- id: 2, name: 'Нет трудомёкости'
				when @extra_id = 2 then ' and (isnull(x.norm_hours,0) = 0)'
				-- id: 3, name: 'Перегрузка работников'
				when @extra_id = 3 then ' and (x.overloads_duration_wk > 0)'
				-- id: 4, name: 'Недоукомлектованные задания'
				when @extra_id = 4 then ' and (x.count_executors < x.norm_count_executors)'
				-- id: 5, name: 'Уволенные сотрудники'
				when @extra_id = 5 then ' and exists(
						select 1 from mfr_plans_jobs_executors e
							join mols on mols.mol_id = e.mol_id
						where e.detail_id = x.id and mols.is_working = 0
						)'
				-- id: 6, name: 'Просроченные задания'
				when @extra_id = 6 then ' and (x.count_executors > 0 
                        and exists(
                            select 1 from mfr_plans_jobs_executors where detail_id = x.detail_id
                                and d_doc < @today
                                and status_id = 0
                            )
                    )
                    '
				-- id: 7, name: 'Нет связанного табеля'
				when @extra_id = 7 then '
                        and exists(
                            select 1 from mfr_plans_jobs_executors where detail_id = x.detail_id
                                and wk_sheet_id is null
                            )'
				-- id: 10, name: 'Исполненные операции'
				when @extra_id = 10 then ' and (x.fact_q > 0)'
			  end
			, case when @filter_attrs = 1 then concat(' and x.item_id in (select product_id from ', @productsQueryTable, ')') end
			)

		declare @fields_base nvarchar(max) = N'		
			@mol_id int,
            @today date,
			@d_doc_from date,
			@d_doc_to date,
			@search nvarchar(max)
			'

		declare @join nvarchar(max) = N'
			join #subjects s on s.id = x.subject_id '
			+ case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.id ' else '' end
			+ case when exists(select 1 from #search_ids) then 'join #search_ids i2 on i2.id = x.plan_job_id' else '' end
			+ case when @searchPost is not null then 'join #post_ids i3 on i3.id = x.detail_id' else '' end

		if @buffer_operation is  null
		begin
			-- @rowscount
				set @sql = N'select @rowscount = count(*) from V_MFR_PLANS_QJOBS2 x ' + @join + @where
				set @fields = @fields_base + ', @rowscount int out'

				exec sp_executesql @sql, @fields,
					@mol_id, @today, @d_doc_from, @d_doc_to, @search,
					@rowscount out
		
			-- @order_by
				declare @order_by nvarchar(200) = N' order by x.priority_sort, x.oper_d_from_plan, x.mfr_number, x.oper_number'
				if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			declare @subquery nvarchar(max) = N'
				(select x.* from V_MFR_PLANS_QJOBS2 x '
				+ @join + @where
				+' ) x ' + @order_by

			-- @sql
			set @sql = N'select x.* from ' + @subquery

			-- optimize on fetch
			if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

			set @fields = @fields_base + ', @offset int, @fetchrows int'

			if @trace = 1 print @sql

			exec sp_executesql @sql, @fields,
				@mol_id, @today, @d_doc_from, @d_doc_to, @search,
				@offset, @fetchrows

		end

		else begin
			set @rowscount = -1 -- dummy
			set @fields = @fields_base

			declare @bufop int = @buffer_operation

			if @buffer_operation = 99
			begin
				set @bufop = 1
				set @obj_type = @obj_type + '-P' -- virtual obj_type (used in products_builder)
			end

			exec objs_buffer_viewhelper 
				@buffer_operation = @bufop, @obj_type = @obj_type, @base_view = @base_view, @pkey = @pkey, @join = @join, @where = @where,
				@fields = @fields out, @sql = @sql out			
			
			exec sp_executesql @sql, @fields, 
				@mol_id, @today, @d_doc_from, @d_doc_to, @search,
				@buffer_id

			if @buffer_operation = 99
				exec products_builder @mol_id = @mol_id,
					@source_name = @base_view,
					@source_key = @pkey,
					@item_name = 'ITEM_ID',
					@obj_type = @obj_type

		end -- buffer_operation
	
	exec drop_temp_table '#subjects,#ids,#search_ids,#post_ids'
end
go
