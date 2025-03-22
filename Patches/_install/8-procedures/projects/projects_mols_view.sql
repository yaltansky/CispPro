if object_id('projects_mols_view') is not null drop proc projects_mols_view
GO
create proc projects_mols_view
	@search varchar(50) = null
as
begin

	set nocount on;

	create table #nodes(
		project_id int,
		node_id int primary key, name varchar(250), name_path varchar(250),
		parent_id int, node hierarchyid, has_childs bit
		)

-- #nodes
	insert into #nodes(project_id, parent_id, node_id, name, name_path)
	select 
		m.project_id,
		case
			when m.parent_id is null then -m.project_id
			else m.parent_id
		end,
		m.mol_node_id,
		m.name, m.name_path
	from projects_mols_nodes m

	UNION ALL
	select
		0, null, -project_id, name, null
	from projects
	where project_id in (select distinct project_id from projects_mols_nodes)
		and type_id = 1
		and status_id >= 0

	declare @children tree_nodes
		insert into @children(node_id, parent_id, num)
		select node_id, parent_id,  
			row_number() over (partition by parent_id order by parent_id, name)
		from #nodes

	declare @nodes tree_nodes
	insert into @nodes exec tree_calc @children

	update x
	set node = xx.node,
		has_childs = 
			case
				when exists(select 1 from #nodes where parent_id = x.node_id) then 1
				else 0
			end
	from #nodes x
		join @nodes as xx on xx.node_id = x.node_id

-- search
	declare @result table(node_id int primary key, node hierarchyid)
	set @search = '%' + @search + '%'
	
	insert into @result
	select node_id, node from #nodes
	where @search is null or name like @search

	insert into @result(node_id)
	select distinct x.node_id
	from #nodes x
		join @result r on r.node.IsDescendantOf(x.node) = 1
	where x.node_id not in (select node_id from @result)

	select 
		PROJECT_ID,
		PARENT_ID,
		MOL_NODE_ID = NODE_ID,
		NAME,
		NAME_PATH,
		HAS_CHILDS,
		cast(node.GetLevel() as int) as LEVEL_ID
	from #nodes
	where node_id in (select node_id from @result)
	order by node
		
	drop table #nodes

end
GO
