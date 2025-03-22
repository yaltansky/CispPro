if object_id('deals_view') is not null drop procedure deals_view
go
-- exec deals_view 700
create proc deals_view
	@mol_id int,
	@subject_id int = null,
	@program_id int = null,	
	@agent_id int = null,
	@response_id int = null,	
	@d_from datetime = null,
	@d_to datetime = null,	
	@search varchar(8000) = null,
	@folder_id int = null,
	@buffer_operation int = null, -- 1 add rows to buffer, 2 remove rows from buffer, 3 get proper transits, 4 classify rows
	@extra_id int = null,
	--
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	@rowscount int = null out,
	@trace bit = 0
as
begin
	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Projects.Programs.Admin')
	
-- @folder_id	
	declare @ids as app_pkids
	if @folder_id is not null insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'

-- @search_ids	
	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)
	if exists(select 1 from @search_ids) set @search = null

-- @search
	set @search = '%' + @search + '%'

-- reglament
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @vendors as app_pkids; insert into @vendors select distinct obj_id from @objects where obj_type = 'vnd'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1)'
		, case
			when @is_admin = 0 then ' and (
				@mol_id in (x.manager_id, mols.chief_id, projects.curator_id, projects.chief_id, projects.admin_id)
				or exists(select 1 from projects_mols where project_id = x.deal_id and mol_id = @mol_id)
        		or exists(select 1 from @subjects where id = x.subject_id)
				or exists(select 1 from @vendros where id = x.vendor_id)
				or exists(select 1 from @budgets where id = x.budget_id)
				)'
		  end
		-- @subject_id
		, case when @subject_id is not null then ' and (x.subject_id = @subject_id)' end
		-- @program_id
		, case when @program_id is not null then ' and (x.program_id = @program_id)' end
		-- @agent_id
		, case when @agent_id is not null then ' and (x.agent_id = @agent_id)' end
		-- @d_from
		, case when @d_from is not null then ' and (x.d_doc >= @d_from)' end
		-- @d_to
		, case when @d_to is not null then ' and (x.d_doc <= @d_to)' end
		-- @response_id
		, case when @response_id is not null then ' and (x.manager_id = @response_id)' end
		-- @search
		, case when @search is not null then 'and (x.content like @search)' end
		-- @extra_id
		, case
			-- { id: -2, name: 'Нет калькуляции' },
			when @extra_id = -2
				then ' and not exists(select 1 from deals_costs where deal_id = x.deal_id)'
			-- { id: -3, name: 'Ошибки калькуляции' }
			when @extra_id = -3
				then ' and x.deal_id in (
					select deal_id
					from (
						select deal_id, quantity * price_transfer_pure as value from deals_products
						where exists(select 1 from deals_costs where deal_id = deals_products.deal_id)
						union all
						select deal_id, -value_bdr
						from deals_costs
						where exists(select 1 from deals_products where deal_id = deals_costs.deal_id)
						) u
					group by deal_id
					having abs(sum(value)) >= 1.00
					)'
			when @extra_id is not null
				then concat(' and (x.status_id = ', @extra_id, ')')
			when @folder_id is not null 
				then 'and (x.status_id <> -1)'
			else 
				'and (x.status_id not in (-1,50))'
		  end
		)

	declare @fields_base nvarchar(max) = N'
		@mol_id int,
		@subject_id int,
		@program_id int,
		@agent_id int,
		@response_id int,		
		@d_from datetime,
		@d_to datetime,
		@search nvarchar(100),
		@subjects app_pkids readonly,
		@vendros app_pkids readonly,
		@budgets app_pkids readonly,
		@ids app_pkids readonly,
		@search_ids app_pkids readonly
	'

	declare @join nvarchar(max) = N'
	left join deals_statuses statuses on statuses.status_id = x.status_id
	left join projects on projects.project_id = x.program_id
	left join subjects on subjects.subject_id = x.subject_id
	left join subjects as sv on sv.subject_id = x.vendor_id
	left join agents on agents.agent_id = x.customer_id
	left join mols on mols.mol_id = x.manager_id '
	+ case when @folder_id is null then '' else 'join @ids i on i.id = x.deal_id ' end
	+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.deal_id' else '' end

	if @buffer_operation is null
	begin
		-- @rowscount
		set @sql = N'select @rowscount = count(*) from deals x ' + @join + @where
		set @fields = @fields_base + ', @rowscount int out'

		-- print 'count(*): ' + @sql + char(10)

		exec sp_executesql @sql, @fields,
			@mol_id, @subject_id, @program_id, @agent_id, @response_id, @d_from, @d_to, @search,		
			@subjects, @vendors, @budgets, @ids, @search_ids,
			@rowscount out
		
		-- @order_by
		declare @order_by nvarchar(50) = N' order by ' + isnull(@sort_expression, 'x.d_doc, x.number')

		-- @sql
		set @sql = N'
		select 
			X.DEAL_ID,
			X.D_DOC,
			X.D_CLOSED,
			X.STATUS_ID,
			STATUS_NAME = STATUSES.NAME,
			SUBJECT_NAME = SUBJECTS.SHORT_NAME,
			VENDOR_NAME = SV.SHORT_NAME,
			AGENT_NAME = AGENTS.NAME,
			MOL_NAME = MOLS.NAME,
			PROGRAM_NAME = PROJECTS.NAME,
			X.NUMBER,
			X.CCY_ID,
			X.VALUE_CCY,
			X.LEFT_CCY,
			X.NOTE,
			HAS_ERRORS = cast(case when errors is not null then 1 else 0 end as bit)
		from deals x '
		+ @join + @where + @order_by
		+ ' offset @offset rows fetch next @fetchrows rows only'

		set @fields = @fields_base + ', @offset int, @fetchrows int'

		if @trace = 1 print '@sql: ' + @sql + char(10)

		exec sp_executesql @sql, @fields,
			@mol_id, @subject_id, @program_id, @agent_id, @response_id, @d_from, @d_to, @search,		
			@subjects, @vendors, @budgets, @ids, @search_ids,
			@offset, @fetchrows
	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

        -- add to buffer
		if @buffer_operation = 1
		begin
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''DL'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''DL'', x.deal_id, @mol_id from deals x '
				+ @join + @where
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @subject_id, @program_id, @agent_id, @response_id, @d_from, @d_to, @search,		
				@subjects, @vendors, @budgets, @ids, @search_ids,
				@buffer_id
		end

        -- remove from buffer
		else if @buffer_operation = 2
		begin
			
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''DL''
					and obj_id in (select deal_id from deals x ' + @join + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @subject_id, @program_id, @agent_id, @response_id, @d_from, @d_to, @search,		
				@subjects, @vendors, @budgets, @ids, @search_ids,
				@buffer_id
		end
	end

end
go