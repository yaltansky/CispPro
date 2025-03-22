if object_id('dogovors_view') is not null drop procedure dogovors_view
go
/*
	declare @r int
	exec dogovors_view 700, @rowscount = @r out
*/
create proc dogovors_view
	@mol_id int,
	@subject_id int = null,
	@status_id int = null,
	@agent_id int = null,
	@response_id int = null,
	@has_original bit = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@search varchar(100) = null,
	@folder_id int = null,	
	@buffer_operation int = null, 
		-- 5 not in any folder
	@extra_id int = null,	
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	@rowscount int out
as
begin
	
	set nocount on;
	
	declare @today datetime = dbo.today()
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Documents.Admin')
	
-- @search
	declare @search_contains nvarchar(100) = '"' + replace(@search, '"', '*') + '"'		
	set @search = '%'+ replace(@search, ' ', '%') + '%'

	if @buffer_operation = 5
	begin
		declare @folderout_id int
		exec objs_folder_notin @mol_id = @mol_id, @folder_id = @folder_id, @folderout_id = @folderout_id out
		set @buffer_operation = null
		set @folder_id = @folderout_id
	end

-- @folder_id	
	declare @ids as app_pkids
	if @folder_id is not null
	begin
		insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'doc'
	end

-- { id: 12, name: 'Фильтр по дате добавления' },
	declare @add_date_from datetime, @add_date_to datetime
	if @extra_id = 12 begin
		set @add_date_from = @d_from; set @d_from = null
		set @add_date_to = @d_to + 1; set @d_to = null
		set @extra_id = null
	end

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = N' where 
		(@folder_id is not null or (x.type_id = 2 and x.has_childs = 0	and x.is_deleted = 0))
		'
		+ case
			when @is_admin = 1 then ' '
			else ' and (x.account_level_id is null
					or @mol_id in (x.mol_id, x.response_id)
					or exists(select 1 from documents_mols where document_id = x.document_id and mol_id = @mol_id and a_read = 1)) '
		  end
		+ '
		and (@subject_id is null or x.subject_id = @subject_id)
		and (@status_id is null or x.status_id = @status_id)
		and (@agent_id is null or x.agent_id = @agent_id)
		and (@has_original is null or isnull(x.has_original,0) = @has_original)'
		-- @d_from
		+ case when @d_from is not null then ' and (x.d_doc >= @d_from)' else ' ' end
		-- @d_to
		+ case when @d_to is not null then ' and (x.d_doc <= @d_to)' else ' ' end
		-- @add_date_from
		+ case when @add_date_from is not null then ' and (x.add_date >= @add_date_from)' else ' ' end
		-- @add_date_to
		+ case when @add_date_to is not null then ' and (x.add_date <= @add_date_to)' else ' ' end
		-- @search
		+ case
			when @search is not null 
				then ' and (
					x.content like @search
					or exists(select 1 from objs where owner_type = ''doc'' and owner_id = x.document_id and contains(content, @search_contains))
					)'
			else ' '
		  end
		-- @extra_id
		+ case
			-- { id: 10, name: 'Добавлены сегодня' },
			when @extra_id = 10 then ' and 
				exists(
					select 1 from documents
					where document_id = x.document_id
						and add_date between @today and @today + 1)'
			-- { id: 11, name: 'Добавлены вчера' },
			when @extra_id = 11 then ' and 
				exists(
					select 1 from documents
					where document_id = x.document_id 
						and add_date between @today-1 and @today)'
			-- { id: 13, name: 'Открытые задачи' },
			when @extra_id = 13 then ' and 
				exists(
					select 1
					from tasks t
						inner join tasks_mols tm on tm.task_id = t.task_id and tm.role_id = 1 and tm.d_executed is null
					where t.refkey = x.refkey
						and tm.mol_id = @mol_id
						and t.status_id <> 5
					)'
			else ' '
		  end

	declare @fields_base nvarchar(max) = N'		
		@mol_id int,
		@subject_id int,
		@status_id int,
		@agent_id int,
		@response_id int,
		@has_original bit,
		@d_from datetime,
		@d_to datetime,
		@add_date_from datetime,
		@add_date_to datetime,
		@today datetime,
		@search varchar(100),
		@search_contains nvarchar(100),
		@folder_id int,
		@ids app_pkids readonly
	'

	declare @inner nvarchar(max) = N'
	inner join documents_statuses s on s.status_id = x.status_id
	left join subjects on subjects.subject_id = x.subject_id	
	left join agents on agents.agent_id = x.agent_id
	left join accounts_levels on accounts_levels.account_level_id = x.account_level_id
	'
	+ case when @folder_id is null then '' else ' inner join @ids ids on ids.id = x.document_id ' end

	-- @rowscount
	set @sql = N'select @rowscount = count(*) from documents x ' + @inner + @where
	set @fields = @fields_base + ', @rowscount int out'

	print 'count(*): ' + @sql + char(10)

	exec sp_executesql @sql, @fields,
		@mol_id, @subject_id, @status_id, @agent_id, @response_id, @has_original,
		@d_from, @d_to, @add_date_from, @add_date_to, @today,
		@search, @search_contains,
		@folder_id, @ids,
		@rowscount out
		
	-- @order_by
	if charindex('status', @sort_expression) > 0
	begin
		if charindex('desc', @sort_expression) > 0
			set @sort_expression = N'x.status_id, x.d_agree_deadline desc'
		else 
			set @sort_expression = N'x.status_id, x.d_agree_deadline'
	end
	declare @order_by nvarchar(50) = N' order by ' + isnull(@sort_expression, 'x.document_id')

	-- @sql
	set @sql = N'
	select 
		X.DOCUMENT_ID,
		X.AGENT_ID,
		X.STATUS_ID,
		STATUS_NAME = S.NAME,
		SUBJECT_NAME = SUBJECTS.SHORT_NAME,
		AGENT_NAME = ISNULL(AGENTS.NAME, X.TEMP_AGENT_NAME),
		ACCOUNT_LEVEL_NAME = ACCOUNTS_LEVELS.NAME,
		X.NAME,
		X.NUMBER,
		X.D_DOC,
		X.D_EXPIRED,
		X.D_AGREE_DEADLINE,
		IS_AGREE_OVERDUE = CAST(CASE WHEN X.D_AGREE_DEADLINE < @TODAY THEN 1 END AS BIT),
		x.HAS_ORIGINAL,
		X.VALUE_CCY,
		X.CCY_ID,
		X.NOTE,
		X.KEY_ATTACHMENTS,
		X.HAS_FILES
	from documents x '
	+ @inner + @where + @order_by
	+ ' offset @offset rows fetch next @fetchrows rows only'

	set @fields = @fields_base + ', @offset int, @fetchrows int'

	print '@sql: ' + @sql + char(10)

	exec sp_executesql @sql, @fields,
		@mol_id, @subject_id, @status_id, @agent_id, @response_id, @has_original,
		@d_from, @d_to, @add_date_from, @add_date_to, @today,
		@search, @search_contains,
		@folder_id, @ids,
		@offset, @fetchrows

end
go
