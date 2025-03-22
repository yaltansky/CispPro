if object_id('documents_calc') is not null drop proc documents_calc
go
create proc documents_calc
	@root_id int = null,
    @trace bit = 0
as
begin

	set nocount on;

	declare @root hierarchyid = (select node from documents where document_id = @root_id)
	create table #docs (document_id int primary key)

	if @root_id is not null
		insert into #docs(document_id) select document_id from documents where node.IsDescendantOf(@root) = 1

	-- hierarchyid
		if @root_id is null	update documents set node = null;

		create table #children(document_id int primary key, parent_id int, num int, node hierarchyid)

			insert #children (document_id, parent_id, num)
			select document_id, parent_id,  
				row_number() over (partition by parent_id order by parent_id, has_childs desc, name)
			from documents where (@root_id is null or document_id in (select document_id from #docs))

		;with nodes(path, document_id)
		as (  
			select 
				cast(
					case
						when @root is null then '/'
						else @root.ToString()
					end + cast(c.num as varchar) + '/' 
					as hierarchyid) as node
				, document_id
			from #children c
			where parent_id is null or parent_id = @root_id			

			union all   
			select   
				cast(p.path.ToString() + cast(c.num as varchar(30)) + '/' as hierarchyid),
				c.document_id
			from #children as c
				join nodes as p on c.parent_id = p.document_id		
			)  
			update x set
				node = p.path,
				level_id = p.path.GetLevel()
			from documents x
				join nodes as p on p.document_id = x.document_id

	-- has_childs
		if @root_id is null
		begin
			-- has_childs
			update x
			set has_childs = 
					case
						when exists(select 1 from documents where parent_id = x.document_id and is_deleted = 0) then 1
						else 0
					end
			from documents x

			-- update name as projects
			update x
			set name = p.name
			from documents x
				inner join projects p on p.project_id = x.key_owner_id
			where x.key_owner like '%projects%'
		end

	-- owner_name
		exec sys_set_triggers 0	
		
            update x
            set owner_name = 
                    case
                        when o.key_owner_type = 'agents' then 'Контрагент ' + a.name
                        when o.key_owner_type = 'projects' then 'Проект ' + p.name
                    end
            from documents x
                join (
                    select node, dbo.strtoken(key_owner, '/', 2) as key_owner_type, key_owner_id
                    from documents
                    where key_owner is not null
                ) o on x.node.IsDescendantOf(o.node) = 1
                left join agents a on a.agent_id = o.key_owner_id
                left join projects p on p.project_id = o.key_owner_id
            where 
                x.key_owner is null
                and (@root_id is null or o.key_owner_id = @root_id)

		exec sys_set_triggers 1

end
GO
