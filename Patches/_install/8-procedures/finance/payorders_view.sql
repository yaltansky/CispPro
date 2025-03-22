if object_id('payorders_view') is not null drop proc payorders_view
go
--  
create proc payorders_view
	@mol_id int,
	-- filter
	@parent_id int = null,
	@type_id int = null,
	@status_id int = null,
	@subject_id int = null,
	@branch_id int = null,
	@project_id int = null,
	@budget_id int = null,
	@invpay_id int = null,
	@date_from datetime = null,
	@date_to datetime = null,
	@folder_id int = null,	
	@buffer_operation int = null, 
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
		-- 5 not in any folder (obsolete)
		-- 6 set status
		-- 7 check budget
	@search nvarchar(max) = null,
	@extra_id int = null, -- not used yet
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 50,
	--
	@rowscount int = null out,
	@trace bit = 0
as
begin

	set nocount on;	
		
	declare @folderout_id int

	-- показать операции, не входящие в папки бюджета
		if @buffer_operation = 6
		begin
			if dbo.isinrole(@mol_id, 'Findocs.Subjects.Admin,Findocs.Subjects.Moderator,Payorders.Moderator') = 1
			begin
				update payorders set status_id = @status_id 
				where payorder_id in (
					select obj_id from objs_folders_details where folder_id = @folder_id
					)
				set @buffer_operation = null
			end
			else begin
				raiserror('У Вас нет доступа к выполнению данной операции.', 16, 1)
				return
			end
		end

		else if @buffer_operation = 7
		begin
			if dbo.isinrole(@mol_id, 'Findocs.Subjects.Admin,Findocs.Subjects.Moderator,Payorders.Moderator') = 1
			begin
				exec payorders_view;30 @mol_id = @mol_id, @folder_id = @folder_id, @folderout_id = @folderout_id out
			end
			else begin
				raiserror('У Вас нет доступа к выполнению данной операции.', 16, 1)
				return
			end

			set @buffer_operation = null
			set @folder_id = @folderout_id
		end

	-- @objects by reglament
		declare @objects as app_objects; insert into @objects exec payorders_reglament @mol_id = @mol_id
		create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'sbj'
		create table #budgets(id int primary key); insert into #budgets select distinct obj_id from @objects where obj_type = 'bdg'

		-- @project_id
		create table #projects_budgets(id int primary key)
		if @project_id is not null
		begin
			insert into #projects_budgets
			select distinct budget_id from (
				-- бюджеты проекта
				select budget_id from budgets where project_id = @project_id
				union all
				-- связанные с проектом сделки
				select budget_id from deals d where exists(
					select 1 from projects_tasks where project_id = @project_id
						and ref_project_id = d.deal_id
						)
				) u
		end

	-- #objs
		create table #objs(id int primary key)
		insert into #objs select owner_id from v_objs_shares
		where mol_id = @mol_id and owner_type = 'po'
			and a_read = 1

	-- #ids
		create table #ids(id int primary key)
		if @folder_id is not null insert into #ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'po'

	-- #search_ids	
		declare @findoc_id int
		create table #search_ids(id int primary key); insert into #search_ids select id from dbo.hashids(@search)

		if exists(select 1 from #search_ids) 
			set @search = null
		
		else if substring(@search, 1, 4) = 'pay:'
		begin
			set @findoc_id = try_parse(substring(@search, 5, 32) as int)
			set @search = null
		end

		else
			set @search = '%' + @search + '%'

	-- @invpay_id
		if @invpay_id is not null
		begin
			declare @inv_id int, @inv_mfr_doc_id int, @inv_item_id int
				select 
					@inv_id = inv_id,
					@inv_mfr_doc_id = mfr_doc_id,
					@inv_item_id = item_id
				from supply_r_invpays_totals
				where row_id = @invpay_id
			
			delete from #ids;
			insert into #ids select distinct payorder_id
			from payorders_materials
			where invoice_id = @inv_id and mfr_doc_id = @inv_mfr_doc_id and item_id = @inv_item_id
		end

	-- prepare
		declare @sql nvarchar(max), @fields_base nvarchar(max), @fields nvarchar(max), @where nvarchar(max),
			@inner_ids nvarchar(500) = concat(' ',
				case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.payorder_id' end,
				case when exists(select 1 from #search_ids) then ' join #search_ids i2 on i2.id = x.payorder_id' end
				)

		set @where = concat(' where (1 = 1) '

			-- reglament
			, concat(
				' and (
					@mol_id in (x.mol_id, x.chief_id)
					or exists(select 1 from #objs where id = x.payorder_id)
					or (
                        x.subject_id in (select id from #subjects)
                        and not exists(select 1 from #budgets)
                        )
                    '
				,
				case when exists(select 1 from #budgets) 
					then ' or exists(select 1 from payorders_details where payorder_id = x.payorder_id and budget_id in (select id from #budgets))'
				end,
				')'
			)

			, case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end
			, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
			, case when @branch_id is not null then concat(' and (x.branch_id = ', @branch_id, ')') end
			, case when @parent_id is not null then concat(' and (x.parent_id = ', @parent_id, ')') end
			, case when @date_from is not null then ' and (x.d_doc >= @date_from)' end
			, case when @date_to is not null then ' and (x.d_doc <= @date_to)' end
				
			-- @status_id
			, case
				when @parent_id is not null then ' and (x.is_deleted = 0)'
				when @status_id is null then ' and (x.status_id >= 0) '
				when @status_id = -10 then ' and (x.status_id not in (-2,-1,0,10)) '
				when @status_id = -20 then ' and (x.parent_id is null and x.has_childs = 1)'
				else ' and (x.status_id = @status_id)'
			end		

			-- @findoc_id
			, case
				when @findoc_id is not null then concat(' and exists(select 1 from payorders_pays where payorder_id = x.payorder_id and findoc_id = ', @findoc_id, ')')
			end
			-- @project_id
			, case
				when @project_id is not null then ' and exists(
					select 1 from payorders_details
					where payorder_id = x.payorder_id 
						and budget_id in (select id from #projects_budgets)
					)'
			end		
			-- @budget_id
			, case
				when @budget_id is not null then ' and exists(select 1 from payorders_details where payorder_id = x.payorder_id and budget_id = @budget_id)'
			end
		)
		
	set @fields_base = N'		
		@mol_id int,
		@date_from datetime,
		@date_to datetime,		
		@search nvarchar(100),
		@project_id int,
		@budget_id int,
		@status_id int,
		@extra_id int
	'
	
	if @buffer_operation is null
	begin
		-- @rowscount
		declare @sql_count nvarchar(max)
		;set @sql_count = N'select @rowscount = count(*) from v_payorders x 
			join mols m on m.mol_id = x.mol_id '
			+ @inner_ids
			+ @where
			+ case when @search is null then ' ' else ' and x.content like @search' end
		;set @fields = @fields_base + ', @rowscount int out'

		exec sp_executesql @sql_count, @fields,
			@mol_id, @date_from, @date_to,
			@search, @project_id, @budget_id, @status_id, @extra_id,
			@rowscount out

		-- selection
		set @sql = N'SELECT * FROM V_PAYORDERS X '
			+ @inner_ids
			+ @where
			+ case when @search is null then ' ' else ' and x.content like @search' end

		if @sort_expression is null
			set @sql = @sql + ' order by x.payorder_id'
		else 
		begin
			if charindex('VALUE_CCY', @sort_expression) = 1 begin
				set @sort_expression = replace(@sort_expression, 'VALUE_CCY', 'ABS(VALUE_CCY)')
				set @sort_expression = @sort_expression + ', D_DOC'
			end
			set @sql = @sql + ' order by ' + @sort_expression
		end

        -- optimize on fetch
		if @rowscount > @fetchrows
		begin
			set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'
		end

		set @fields = @fields_base + ', @offset int, @fetchrows int'

		if @trace = 1 print @sql

		exec sp_executesql @sql, @fields,
			@mol_id, @date_from, @date_to,
			@search, @project_id, @budget_id, @status_id, @extra_id,
			@offset, @fetchrows
	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id
		declare @buffer_where nvarchar(max)
		set @buffer_where = @where + case when @search is null then ' ' else ' and x.content like @search' end

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''PO'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''PO'', x.payorder_id, @mol_id from v_payorders x '
				+ @inner_ids
				+ @buffer_where				
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @date_from, @date_to,
				@search, @project_id, @budget_id, @status_id, @extra_id,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_id in (select payorder_id from payorders x ' + @buffer_where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			exec sp_executesql @sql, @fields,
				@mol_id, @date_from, @date_to,
				@search, @project_id, @budget_id, @status_id, @extra_id,
				@buffer_id
		end
	end
		
    exec drop_temp_table '#subjects,#budgets,#projects_budgets,#objs,#ids,#search_ids'
end
GO
-- helper: create folder PAYORDER-others-<MOL_ID>
create proc payorders_view;10
	@mol_id int,
	@folderout_id int out
as
begin

	declare @folders_key varchar(50) = 'PAYORDER'
	declare @others_folder_key varchar(50) = @folders_key + '-others-' + cast(@mol_id as varchar)
	declare @others_folder_id int = (select folder_id from objs_folders where keyword = @others_folder_key)

	if @others_folder_id is null begin
		insert into objs_folders(keyword, name, add_mol_id) values(@others_folder_key, @others_folder_key, @mol_id)
		set @others_folder_id = @@identity
	end

	set @folderout_id = @others_folder_id
end
go
-- helper: проверка бюджета
create proc payorders_view;30
	@mol_id int,
	@folder_id int,
    @folderout_id int out
as
begin
	create table #details (
		budget_id int,
		article_id int,
		plan_ccy decimal(18,2),
		fact_ccy decimal(18,2),
		--
		constraint pk primary key (budget_id, article_id)
    	)

	insert into #details(budget_id, article_id)
	select x.budget_id, x.article_id
	from payorders_details x
		join objs_folders_details fd on fd.folder_id = @folder_id and fd.obj_id = x.payorder_id
	where x.budget_id + x.article_id is not null
	group by x.budget_id, x.article_id

	update x
	set plan_ccy = 0, fact_ccy = 0, order_ccy = 0
	from payorders_details x
		join objs_folders_details fd on fd.folder_id = @folder_id and fd.obj_id = x.payorder_id
	
	-- #plan_ccy
	update x
	set plan_ccy = abs(b.plan_dds)
	from #details x
		join budgets_totals b on b.budget_id = x.budget_id and b.article_id = x.article_id
	
	-- #fact_ccy
	update x
	set fact_ccy = abs(f.value_ccy)
	from #details x
		join (
			select budget_id, article_id, sum(value_ccy) as value_ccy
			from findocs
			group by budget_id, article_id
		) f on f.budget_id = x.budget_id and f.article_id = x.article_id

	-- #plan_ccy, #fact_ccy -> payorders_details
	update x
	set plan_ccy = xx.plan_ccy,
		fact_ccy = xx.fact_ccy
	from payorders_details x
		join objs_folders_details fd on fd.folder_id = @folder_id and fd.obj_id = x.payorder_id
		join #details xx on xx.budget_id = x.budget_id and xx.article_id = x.article_id

	-- order_ccy
	update x
	set order_ccy = (
			select sum(od.value_ccy)
			from payorders o
				join payorders_details od on od.payorder_id = o.payorder_id
			where od.budget_id = x.budget_id and od.article_id = x.article_id
				and o.status_id in (2,3)
				and o.payorder_id <> x.payorder_id
			)
	from payorders_details x
		join objs_folders_details fd on fd.folder_id = @folder_id and fd.obj_id = x.payorder_id

	-- check budget
	exec payorders_view;10 @mol_id = @mol_id, @folderout_id = @folderout_id out
	
	delete from objs_folders_details where folder_id = @folderout_id
	
	insert objs_folders_details(folder_id, obj_id, add_mol_id)
	select distinct @folderout_id, x.payorder_id, @mol_id
	from payorders_details x
		join objs_folders_details fd on fd.folder_id = @folder_id and fd.obj_id = x.payorder_id
	where (isnull(x.plan_ccy,0) - isnull(x.fact_ccy,0) - isnull(x.order_ccy,0) - isnull(x.value_ccy,0)) < 0

	drop table #details	
end
go
