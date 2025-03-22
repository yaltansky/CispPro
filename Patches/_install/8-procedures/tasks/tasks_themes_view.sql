if object_id('tasks_themes_view') is not null drop proc tasks_themes_view
go
create proc tasks_themes_view
	@mol_id int,
	@search varchar(100) = null,
	@with_analyzer bit = null,
	@parent_id int = null
as
begin

	set nocount on;

	set @search = '%' + @search + '%'

	-- check access to theme
	create table #avail (theme_id int primary key)
	
	if @with_analyzer = 1
	begin
		create table #mols_nodes (
			theme_id int, project_id int, mol_node_id int, node hierarchyid,
			primary key (theme_id, mol_node_id)
			)

			insert into #mols_nodes(theme_id, project_id, mol_node_id, node)
			select distinct mn.theme_id, pmn.project_id, pmn.mol_node_id, pmn.node
			from tasks_themes_mols_nodes mn
				join projects_mols_nodes pmn on pmn.mol_node_id = mn.mol_node_id

			insert into #mols_nodes(theme_id, project_id, mol_node_id)
			select distinct xx.theme_id, x.project_id, x.mol_node_id
			from projects_mols_nodes x
				join #mols_nodes xx on xx.project_id = x.project_id and x.node.IsDescendantOf(xx.node) = 1
			where not exists(select 1 from #mols_nodes where theme_id = xx.theme_id and mol_node_id = x.mol_node_id)

		insert into #avail(theme_id)
		select theme_id from tasks_themes x
		where x.is_deleted = 0
			and x.analyzer_id is not null
			and (
				not exists(select 1 from tasks_themes_mols_nodes where theme_id = x.theme_id)
				or exists(
					select 1 from projects_mols pm
						join #mols_nodes x on x.mol_node_id = pm.parent_id 
					where theme_id = x.theme_id
						and pm.mol_id = @mol_id
				)
			)
		drop table #mols_nodes
	end
	else
		insert into #avail select theme_id from tasks_themes where has_childs = 0 and is_deleted = 0

	declare @nodes table(theme_id int primary key, node hierarchyid)
	
	-- find nodes
	if @parent_id is null
	begin
		insert into @nodes
		select x.theme_id, x.node
		from tasks_themes x
			join #avail a on a.theme_id = x.theme_id
		where (@search is null or name like @search)
			and has_childs = 0

		-- + parents
		insert into @nodes(theme_id)
		select distinct x.theme_id
		from tasks_themes x
			join @nodes n on n.node.IsDescendantOf(x.node) = 1
		where x.theme_id not in (select theme_id from @nodes)
			and x.has_childs = 1
			and x.is_deleted = 0
	end

	else 
		insert into @nodes(theme_id)
		select x.theme_id 
		from tasks_themes x
			join #avail a on a.theme_id = x.theme_id
		where x.parent_id = @parent_id

	select 
		NODE_ID = THEME_ID,
		x.*
	from tasks_themes x
	where x.theme_id in (select theme_id from @nodes)
	order by node

    drop table #avail

end
GO
