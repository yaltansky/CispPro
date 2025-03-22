if object_id('documents_tree_view') is not null drop procedure documents_tree_view
go
create proc documents_tree_view
	@mol_id int,	
	@root_id int = null,
	@parent_id int = null,
	@search varchar(50) = null,
	@status_id int = null,
	@extra_id int = null,
	@date_from datetime = null,
	@date_to datetime = null,
	@filter_mol_id int = null,
	@ids varchar(max) = null,
	@folder_id int = null
as
begin
	
	set nocount on;

-- params
	if @date_from is not null or @date_to is not null set @search = '%'
	if @search is not null set @ids = null

-- prepare
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Documents.Admin')	
	declare @root hierarchyid; select @root = node from documents where document_id = @root_id	
	declare @root_node hierarchyid = (select node from documents where document_id = @root_id)

	create table #result(document_id int, node hierarchyid, has_childs bit)
		create index ix_result on #result(document_id)

-- root query
	if @parent_id is not null
		insert into #result
		select d.document_id, d.node, d.has_childs
		from documents d
		where parent_id = @parent_id
			and d.is_deleted = 0

	else if @search is null
		and @status_id is null
		and @extra_id is null
		and @date_from is null
		and @date_to is null
		and @filter_mol_id is null
		and @ids is null		
	begin
		insert into #result
		select d.document_id, d.node, d.has_childs
		from documents d
		where isnull(parent_id,0) = isnull(@root_id,0)
			and d.is_deleted = 0
	end	

-- refresh for ids (ids - the set of parents)
	else if @ids is not null
	begin		
		-- #document_ids
		create table #document_ids(document_id int primary key)
		if @ids is not null
			insert into #document_ids select distinct item from dbo.str2rows(@ids, ',')

		-- root
		insert into #result(document_id, node, has_childs)
		select document_id, node, has_childs from documents 
		where isnull(@root_id,0) = isnull(parent_id,0)

		-- expanded parents
		insert into #result(document_id, node, has_childs)
		select d.document_id, d.node, d.has_childs
		from documents d
		where exists(select 1 from #document_ids where document_id = d.document_id)
			and not exists(select 1 from #result where document_id = d.document_id)
		
		-- + their childs
		insert into #result(document_id, node, has_childs)
		select d.document_id, d.node, d.has_childs
		from documents d
			inner join #document_ids ids on ids.document_id = d.parent_id
	end

-- search query
	else begin		
		declare @document_id int
		
		if dbo.hashid(@search) is not null
		begin
			set @document_id = dbo.hashid(@search)
			set @search = null
		end

		declare @add_date_from datetime, @add_date_to datetime
		if @extra_id = 12 begin
			set @add_date_from = @date_from; set @date_from = null
			set @add_date_to = @date_to + 1; set @date_to = null
			set @extra_id = null
		end

		declare @text_search nvarchar(100) = isnull('"' + replace(@search, '"', '*') + '"', '*')
		declare @today datetime = dbo.today()
		declare @expiration_soon datetime = dateadd(d, 7, @today)

		set @search = '%' + @search + '%'

		-- search
		insert into #result(document_id, node, has_childs)
		select d.document_id, d.node, d.has_childs
		from documents d
			left join agents a on a.agent_id = d.agent_id
		where (@document_id is null or d.document_id = @document_id)
			and (@search is null 
				or d.content like @search
				--contains(content, @text_search)
				)
			and (
				   (@status_id is null and d.is_deleted = 0)
				or (@status_id = -1 and d.is_deleted = 1)
				or d.status_id = @status_id
				)
			and (@extra_id is null
				or (@extra_id = 1 and document_id in (select document_id from tasks where refkey = '/documents/'+cast(d.document_id as varchar) and type_id = 2 and status_id <> 5))
				or (@extra_id = 2 and document_id in (select document_id  from tasks where refkey = '/documents/'+cast(d.document_id as varchar) and type_id = 3 and status_id <> 5))
				or (@extra_id = 3 and document_id in (select document_id from documents where d_expired between @today + 1 and @expiration_soon))
				or (@extra_id = 4 and document_id in (select document_id from documents where d_expired < @today))
				-- id: 10, name: 'Добавлены сегодня'
				or (@extra_id = 10 and document_id in (select document_id from documents where document_id = d.document_id and add_date between @today and @today + 1))
				-- id: 11, name: 'Добавлены вчера'
				or (@extra_id = 11 and document_id in (select document_id from documents where document_id = d.document_id and add_date between @today - 1 and @today))
				-- id: 13, name: 'Открытые задачи'
				or (@extra_id = 13 and exists(
						select 1
						from tasks t
							inner join tasks_mols tm on tm.task_id = t.task_id and tm.role_id = 1 and tm.d_executed is null
						where t.refkey = d.refkey
							and tm.mol_id = @mol_id
							and t.status_id <> 5
							and d.status_id <> 10
					))
				-- id: 100, name: 'Мои документы'
				or (@extra_id = 100 and (d.mol_id = @mol_id or exists(select 1 from documents_mols where document_id = d.document_id and mol_id = @mol_id and a_read = 1)))
				)

			and (@date_from is null or d.d_doc >= @date_from)
			and (@date_to is null or d.d_doc <= @date_to)
			and (@add_date_from is null or d.add_date >= @add_date_from)
			and (@add_date_to is null or d.add_date <= @add_date_to)

			and (@filter_mol_id is null
				or @filter_mol_id in (mol_id, response_id)
				or exists(select 1 from documents_mols where document_id = d.document_id and mol_id = @filter_mol_id and a_read = 1)
				)
			and d.has_childs = 0
			and (@root_node is null or d.node.IsDescendantOf(@root_node) = 1)
	end

-- @allowed
	declare @allowed as app_pkids
		insert into @allowed
			select document_id
			from documents d
			where has_childs = 0
				and (@is_admin = 1
					or account_level_id is null
					or @mol_id in (d.mol_id, d.response_id)
					or exists(select 1 from documents_mols where document_id = d.document_id and mol_id = @mol_id and a_read = 1)
					)

	delete from #result
	where has_childs = 0
		and document_id not in (select id from @allowed)

-- get all parents
	if @parent_id is null
	begin
		insert into #result(document_id, node)
		select distinct d.document_id, d.node
		from documents d
			join #result r on r.node.IsDescendantOf(d.node) = 1
		where d.has_childs = 1
			and (@root_node is null 
				or (d.node.IsDescendantOf(@root_node) = 1 and d.document_id <> @root_id)
				)
	end

-- return results	
	select 
		D.DOCUMENT_ID AS NODE_ID,
		S.NAME AS STATUS_NAME,
		D.MOL_ID,
		D.STATUS_ID,
		D.PARENT_ID,
		D.KEY_ATTACHMENTS,
		D.HAS_FILES,
		D.HAS_CHILDS,
		D.LEVEL_ID,
		D.IS_DELETED,
		D.SORT_ID,
		--
        D.NAME,
        D.NOTE,
        ISNULL(D.D_EXPIRED, D.D_DOC) AS D_DOC,
		LEV.NAME AS ACCOUNT_LEVEL,
		D.KEY_OWNER
	from documents d
		join documents_statuses s on s.status_id = d.status_id
		left join accounts_levels lev on lev.account_level_id = d.account_level_id
	where d.document_id in (select distinct document_id from #result)
	order by d.node

end
go