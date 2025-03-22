if object_id('findocs_view') is not null drop proc findocs_view
go
-- exec findocs_view 1000, @budget_id = 273
create proc findocs_view
	@mol_id int,
	-- filter
	@account_id int = null,
	@subject_id int = null,
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@project_id int = null,
	@budget_id int = null,
	@article_id int = null,	
	@goal_account_id int = null,
	@goal_sum_id int = null,
	@invpay_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, -- 1 add rows to buffer, 2 remove rows from buffer, 3 get proper transits, 4 classify rows
	@is_input bit = null, -- null - all, 1 - value_ccy > 0, 0 - value_ccy < 0	
	@search varchar(max) = null,
	@extra_id int = null,
		-- 1 - не классифицировано
		-- 2 - классифицировано
		-- 3 - подобрать транзиты
		-- 4 - классифицировать оплаты
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 300,
	--
	@rowscount int = null out,
	@trace bit = 0
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- @objects by reglament
		declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'SBJ'
		create table #budgets(id int primary key); insert into #budgets select distinct obj_id from @objects where obj_type = 'bdg'
		declare @all_budgets bit = case when exists(select 1 from #budgets where id = -1) then 1 else 0 end

		create table #budgets_tmp(id int primary key)

		if @budget_id is not null
			insert into #budgets_tmp select @budget_id
    -- @goal_sum_id
		create table #goal_accounts(id int primary key)
		create table #articles(id int primary key)

		if @goal_sum_id is not null
		begin
			declare @goal_id int, @goal_node hierarchyid, @group_id varchar(32)
			select 
				@goal_id = fin_goal_id,
				@group_id = group_id,
				@folder_id = nullif(folder_id, 0),
				@goal_node = node
			from fin_goals_sums
			where id = @goal_sum_id
			
			if @group_id = 'fin_goals_accounts'
				insert into #goal_accounts
				select distinct goal_account_id from fin_goals_sums
				where fin_goal_id = @goal_id
					and mol_id = @mol_id
					and node.IsDescendantOf(@goal_node) = 1
					and goal_account_id is not null

			else if @group_id = 'budgets_by_vendors'
				insert into #budgets_tmp
				select distinct budget_id from fin_goals_sums
				where fin_goal_id = @goal_id
					and mol_id = @mol_id
					and node.IsDescendantOf(@goal_node) = 1
					and (
						@all_budgets = 1
						or budget_id in (select budget_id from #budgets)
						)
					and budget_id is not null

			else if @group_id = 'bdr_articles'
				insert into #articles
				select distinct article_id from fin_goals_sums
				where fin_goal_id = @goal_id
					and mol_id = @mol_id
					and node.IsDescendantOf(@goal_node) = 1
					and article_id is not null
		end

		if exists(select 1 from #budgets_tmp)
		begin
			delete from #budgets
			insert into #budgets select id from #budgets_tmp
		end

		declare @some_budgets bit = 
			case 
				when not exists(select 1 from @objects) then 1
				when exists(select 1 from #budgets where id <> -1) then 1
				else 0 
			end
	-- #goal_accounts
		if @goal_account_id is not null
		begin
			declare @goal_account hierarchyid = (select node from fin_goals_accounts where goal_account_id = @goal_account_id)
			insert into #goal_accounts select distinct goal_account_id from fin_goals_accounts where node.IsDescendantOf(@goal_account) = 1
		end
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
	-- #articles
		if @article_id is not null
		begin
			declare @article hierarchyid = (select node from bdr_articles where article_id = @article_id)
			insert into #articles select distinct article_id from bdr_articles where node.IsDescendantOf(@article) = 1
		end
	-- folder
		create table #ids(id int primary key)
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		if @folder_id is not null insert into #ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'fd'
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
			insert into #ids select distinct findoc_id
			from supply_r_invpays
			where inv_id = @inv_id and mfr_doc_id = @inv_mfr_doc_id and item_id = @inv_item_id
				and findoc_id is not null
		end
	-- cast @search
        declare @search_text nvarchar(500)
		create table #search_ids(id int primary key); insert into #search_ids select distinct id from dbo.hashids(@search)
			
        declare @search_param nvarchar(max) = '%' + replace(@search, ' ', '%') + '%'

		if exists(select 1 from #search_ids)
			set @search = null
		else begin
			set @search_text = '"' + replace(@search, '"', '*') + '"'
            set @search = null
        end
	
    build_sql:
		declare @sql nvarchar(max), @fields nvarchar(max)

		declare @where nvarchar(max) = concat(
			' where (1=1) '
			
			, case when @all_budgets = 1 and @some_budgets = 0 then ' and x.subject_id in (select id from #subjects)' end
			, case when @subject_id is not null then ' and (x.subject_id = @subject_id)' end
			, case when @account_id is not null then ' and (x.account_id = @account_id)' end
			, case when @d_doc_from is not null then ' and (x.d_doc >= @d_doc_from)' end		
			, case when @d_doc_to is not null then ' and (x.d_doc <= @d_doc_to)' end
			, case when @search_text is not null then ' and contains(x.content, @search_text)' end
			, case when @search is not null then ' and (x.content like @search)' end

			-- #goal_accounts, @some_budgets, #articles
			, case
                when 
                    exists(select 1 from #goal_accounts) 
                    or @some_budgets = 1
                    or exists(select 1 from #articles) 
                        then concat(' and exists(
                                    select 1 from findocs#
                                    where findoc_id = x.findoc_id',
                                        case when exists(select 1 from #goal_accounts) then
                                            ' and goal_account_id in (select id from #goal_accounts)'
                                        end,
                                        case when @some_budgets = 1 then
                                            ' and budget_id in (select id from #budgets)'
                                        end,
                                        case when exists(select 1 from #articles) then
                                            ' and article_id in (select id from #articles)'
                                        end
                                    , ')'
                                )
				end

			-- @project_id
			, case
					when @project_id is not null then ' and exists(
						select 1 from findocs#
						where findoc_id = x.findoc_id
							and budget_id in (select id from #projects_budgets)
						)'
				end		

			-- @extra_id
			, case
					when @extra_id is null then ' and (x.status_id <> -1)'
					when @extra_id = 1 then 'and (x.status_id = 0)'
					when @extra_id = 2 then 'and (x.status_id in (1,2))'
					-- внутренние операции
					when @extra_id = 3 then 'and (x.agent_id in (select pred_id from subjects where pred_id is not null))'
					-- консолидация
					when @extra_id = 4 then 'and (x.agent_id not in (select pred_id from subjects where pred_id is not null))'
				end		

			-- @is_input
			, case
					when @is_input = 1 then 'and exists(select 1 from findocs# where findoc_id = x.findoc_id and value_ccy > 0)'
					when @is_input = 0 then 'and exists(select 1 from findocs# where findoc_id = x.findoc_id and value_ccy < 0)'
				end
			)

		declare @fields_base nvarchar(max) = N'		
			@d_doc_from datetime,
			@d_doc_to datetime,
			@subject_id int,
			@account_id int,		
			@search nvarchar(max),
			@search_text nvarchar(500),
			@extra_id int
		'

		declare @inner nvarchar(max) = 
			case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids ids on ids.id = x.findoc_id ' else '' end
			+ case when exists(select 1 from #search_ids) then 'join #search_ids i on i.id = x.findoc_id' else '' end

    -- @rowscount
        set @sql = N'select @rowscount = count(*) from findocs x with(nolock) ' + @inner + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @d_doc_from, @d_doc_to, @subject_id, @account_id,
            @search, @search_text, @extra_id,
            @rowscount out
    
        if @rowscount = 0 and @search_text is not null
        begin
            set @search = @search_param
            set @search_text = null
            goto build_sql
        end

    -- @buffer_operation
		if @buffer_operation is not null
		begin
			set @rowscount = -1 -- dummy

			declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

			if @buffer_operation = 1
			begin
				-- add to buffer
				set @sql = N'
					delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''FD'';
					insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
					select @buffer_id, ''FD'', x.findoc_id, @mol_id from findocs x '
					+ @inner + @where
				set @fields = @fields_base + ', @buffer_id int, @mol_id int'

                if @trace = 1 print @sql
				exec sp_executesql @sql, @fields,
					@d_doc_from, @d_doc_to, @subject_id, @account_id,
					@search, @search_text, @extra_id,
					@buffer_id, @mol_id
			end

			else if @buffer_operation = 2
			begin
				-- remove from buffer
				set @sql = N'
					delete from objs_folders_details
					where folder_id = @buffer_id
						and obj_type = ''FD''
						and obj_id in (select findoc_id from findocs x ' + @where + ')'
				set @fields = @fields_base + ', @buffer_id int'
				
				exec sp_executesql @sql, @fields,
					@d_doc_from, @d_doc_to, @subject_id, @account_id,
					@search, @search_text, @extra_id,
					@buffer_id
			end

			-- подобрать транзиты
			else if @buffer_operation = 3
			begin
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'FD', findoc_id, @mol_id
				from (
					select distinct y.findoc_id 
					from findocs y
						cross apply findocs yy					
							join subjects syy on syy.subject_id = yy.subject_id
							join subjects sy on sy.pred_id = yy.agent_id
					where yy.findoc_id in (select obj_id from objs_folders_details where folder_id = @buffer_id and obj_type = 'FD')
						and y.subject_id = sy.subject_id
						and y.agent_id = syy.pred_id
						and y.d_doc = yy.d_doc
						and abs(y.value_ccy) = abs(yy.value_ccy)
					) r
				where not exists(select 1 from objs_folders_details where folder_id = @buffer_id and obj_id = r.findoc_id and obj_type = 'FD')
			end

			-- классифицировать оплаты
			else if @buffer_operation = 4
			begin
				declare @buffer table(findoc_id int primary key)
				insert into @buffer select distinct obj_id from objs_folders_details where folder_id = @buffer_id and obj_type = 'FD'

				if @budget_id is not null
				begin				
					update findocs set budget_id = @budget_id
					where findoc_id in (select findoc_id from @buffer)

					update findocs_details set budget_id = @budget_id
					where findoc_id in (select findoc_id from @buffer)
				end

				if @article_id is not null
				begin
					update findocs set article_id = @article_id
					where findoc_id in (select findoc_id from @buffer)

					update findocs_details set article_id = @article_id
					where findoc_id in (select findoc_id from @buffer)
				end
			end	
		end

    -- select
		else begin

			-- @order_by
			declare @order_by nvarchar(50) = N' order by x.findoc_id'

			if @sort_expression is not null
			begin
				if charindex('value_ccy', @sort_expression) = 1 begin
					set @sort_expression = replace(@sort_expression, 'value_ccy', 'abs(value_ccy)')
					set @sort_expression = @sort_expression + ', d_doc'
				end
				set @order_by = N' order by ' + @sort_expression
			end

			declare @subquery nvarchar(max) = N'(
			select x.*
				, SUBJECT_NAME = s.NAME
				, SUBJECT_SHORT_NAME = s.SHORT_NAME
				, ACCOUNT_NAME = ac.NAME
				, AGENT_NAME = A.NAME
				, GOAL_ACCOUNT_NAME = GA.NAME
				, BUDGET_NAME = B.NAME
				, ARTICLE_NAME = BA.NAME
			from findocs x with(nolock)
				left join subjects s on s.subject_id = x.subject_id
				left join findocs_accounts ac with(nolock) on ac.account_id = x.account_id
				left join agents a with(nolock) on a.agent_id = x.agent_id
				left join fin_goals_accounts ga with(nolock) on ga.goal_account_id = x.goal_account_id
				left join budgets b with(nolock) on b.budget_id = x.budget_id
				left join bdr_articles ba on ba.article_id = x.article_id '
			+ @inner + @where
			+' ) x ' + @order_by

			-- @sql
				set @sql = N'select x.* from ' + @subquery

			-- optimize on fetch
				if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

				set @fields = @fields_base + ', @offset int, @fetchrows int'

				if @trace = 1 print '@sql: ' + @sql + char(10)

				exec sp_executesql @sql, @fields,
					@d_doc_from, @d_doc_to, @subject_id, @account_id,
					@search, @search_text, @extra_id,
					@offset, @fetchrows
		end -- if
end
go
