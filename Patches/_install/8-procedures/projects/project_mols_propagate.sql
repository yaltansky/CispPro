if object_id('project_mols_propagate') is not null
	drop proc project_mols_propagate
GO

create proc project_mols_propagate
	@project_id int,
	@tree_id int
as
begin

	declare @node hierarchyid = (select node from projects_mols where id = @tree_id)

-- delete personal permissions
	delete x from projects_mols_sections_meta x
		inner join projects_mols m on m.project_id = x.project_id 
			and m.id = x.tree_id
			and m.node.IsDescendantOf(@node) = 1
	where x.project_id = @project_id
		and m.node <> @node

-- set inherited flag
	update projects_mols
	set inherited_access = 1
	where node.IsDescendantOf(@node) = 1
		and node <> @node

end
GO
