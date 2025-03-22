if object_id('documents_view') is not null drop procedure documents_view
go
-- exec documents_view 1000, @search='#38066'
create proc documents_view
	@mol_id int,
	@type_id int = null,
	@subject_id int = null,
	@agent_id int = null,
	@project_id int = null,
	@status_id int = null,
	@response_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@search varchar(max) = null,
	@folder_id int = null,	
	@extra_id int = null,	
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	@rowscount int = null out,
	@trace bit = 0
as
begin
	set nocount on;
	
	declare @today datetime = dbo.today()
	declare @expiration_soon datetime = dateadd(d, 7, @today)
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin,Documents.Admin')
	
-- @document_id
	declare @document_id int
	if dbo.hashid(@search) is not null
	begin
		set @document_id = dbo.hashid(@search)
		set @search = null
	end
-- @search
    -- #search_ids
    create table #search_ids(id int primary key)
    if @search is not null
        insert into #search_ids select distinct id from dbo.hashids(@search)
    if exists(select 1 from #search_ids) set @search = null
    else set @search = '%' + replace(@search, ' ', '%') + '%'
-- @folder_id	
	declare @ids as app_pkids
	if @folder_id is not null
	begin
		insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'doc'
	end
-- id: 12, name: 'Фильтр по дате добавления'
	declare @add_date_from datetime, @add_date_to datetime
	if @extra_id = 12 begin
		set @add_date_from = @d_from; set @d_from = null
		set @add_date_to = @d_to + 1; set @d_to = null
		set @extra_id = null
	end
-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(N' where 
		    (x.has_childs = 0)
		and (@subject_id is null or x.subject_id = @subject_id)
		and ((@status_id is null and x.status_id >= 0) or x.status_id = @status_id)
		and (@agent_id is null or x.agent_id = @agent_id)
		'
		, case when @is_admin = 0 then 
			' and (x.account_level_id is null
				or @mol_id in (x.mol_id, x.response_id, m.chief_id)
				or exists(select 1 from documents_mols where document_id = x.document_id and mol_id = @mol_id and a_read = 1)) '
		  end
		, case when @type_id is not null then ' and (x.type_id = @type_id)' end
		, case when @d_from is not null then ' and (x.d_doc >= @d_from)' end
		, case when @d_to is not null then ' and (x.d_doc <= @d_to)' end
		, case when @add_date_from is not null then ' and (x.add_date >= @add_date_from)' end
		, case when @add_date_to is not null then ' and (x.add_date <= @add_date_to)' end
		, case when @document_id is not null then concat(' and (x.document_id = ', @document_id, ')') end
		, case when @search is not null then ' and (x.content like @search)' end		
		
		-- @extra_id
		, case
			-- id: 1, name: 'На согласовании'
			when @extra_id = 1 then ' and document_id in (select document_id from tasks where refkey = ''/documents/'' + cast(x.document_id as varchar) and type_id = 2 and status_id != 5)'
			-- id: 2, name: 'На ознакомлении'
			when @extra_id = 2 then ' and document_id in (select document_id  from tasks where refkey = ''/documents/''+cast(x.document_id as varchar) and type_id = 3 and status_id != 5)'
			-- id: 3, name: 'Срок действия истекает'
			when @extra_id = 3 then ' and document_id in (select document_id from documents where d_expired between @today + 1 and @expiration_soon)'
			-- id: 4, name: 'Срок действия истёк'
			when @extra_id = 4 then ' and document_id in (select document_id from documents where d_expired < @today)'
			-- id: 10, name: 'Добавлены сегодня'
			when @extra_id = 10 then ' and 
				exists(
					select 1 from documents
					where document_id = x.document_id
						and add_date between @today and @today + 1)'
			-- id: 11, name: 'Добавлены вчера'
			when @extra_id = 11 then ' and 
				exists(
					select 1 from documents
					where document_id = x.document_id 
						and add_date between @today-1 and @today)'
			-- id: 13, name: 'Открытые задачи'
			when @extra_id = 13 then ' and 
				exists(
					select 1
					from tasks t
						inner join tasks_mols tm on tm.task_id = t.task_id and tm.role_id = 1 and tm.d_executed is null
					where t.refkey = x.refkey
						and tm.mol_id = @mol_id
						and t.status_id != 5
					)'
			-- id: 100, name: 'Мои документы'
			when @extra_id = 100 then ' and (x.mol_id = @mol_id)'
		  end
		)

	declare @fields_base nvarchar(max) = N'		
		@mol_id int,
		@type_id int,
		@subject_id int,
		@status_id int,
		@agent_id int,
		@response_id int,		
		@d_from datetime,
		@d_to datetime,
		@add_date_from datetime,
		@add_date_to datetime,
		@today datetime,
		@expiration_soon datetime,
		@search varchar(max),
		@folder_id int,
		@ids app_pkids readonly
	'

	declare @inner nvarchar(max) = N'
	join documents_types t on t.type_id = x.type_id
	join documents_statuses s on s.status_id = x.status_id
	left join agents on agents.agent_id = x.agent_id
	left join mols m on m.mol_id = isnull(x.response_id, x.mol_id)
	left join subjects on subjects.subject_id = x.subject_id	
	'
	+ case when exists(select 1 from @ids) then ' join @ids ids on ids.id = x.document_id ' else '' end
    + case when exists(select 1 from #search_ids) then ' join #search_ids i2 on i2.id = x.document_id' else '' end

	-- @rowscount
	set @sql = N'select @rowscount = count(*) from documents x ' + @inner + @where
	set @fields = @fields_base + ', @rowscount int out'

	if @trace = 1 print 'count(*): ' + @sql + char(10)

	exec sp_executesql @sql, @fields,
		@mol_id, @type_id, @subject_id, @status_id, @agent_id, @response_id,
		@d_from, @d_to, @add_date_from, @add_date_to, @today, @expiration_soon,
		@search,
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
	declare @order_by nvarchar(50) = N' order by ' + isnull(@sort_expression, 'x.document_id desc')

	-- @sql
	set @sql = N'
	select 
		X.DOCUMENT_ID,
		X.TYPE_ID,
		TYPE_NAME = T.NAME,
		STATUS_ID = CASE WHEN X.IS_DELETED = 0 THEN X.STATUS_ID ELSE -1 END,
		STATUS_NAME = CASE WHEN X.IS_DELETED = 0 THEN S.NAME ELSE ''удалено'' END,
		SUBJECT_NAME = SUBJECTS.SHORT_NAME,
		OWNER_NAME,
		AGENT_NAME = ISNULL(AGENTS.NAME, X.TEMP_AGENT_NAME),
		X.NAME,
		NUMBER = ISNULL(X.NUMBER, ''не указан''),
		X.D_DOC,
		MOL_NAME = M.NAME,
		x.ADD_DATE,
		X.D_EXPIRED,
		X.VALUE_CCY,
		X.CCY_ID,
		NOTE = concat(x.name, case when x.note is null then '''' else '', '' end, x.note),
		X.KEY_ATTACHMENTS,
		X.HAS_FILES
	from documents x '
	+ @inner + @where + @order_by
	+ ' offset @offset rows fetch next @fetchrows rows only'

	set @fields = @fields_base + ', @offset int, @fetchrows int'

	if @trace = 1 print '@sql: ' + @sql + char(10)

	exec sp_executesql @sql, @fields,
		@mol_id, @type_id, @subject_id, @status_id, @agent_id, @response_id,
		@d_from, @d_to, @add_date_from, @add_date_to, @today, @expiration_soon,
		@search,
		@folder_id, @ids,
		@offset, @fetchrows

end
go
