if object_id('tree_calc') is not null drop procedure tree_calc
go
create procedure tree_calc
	@nodes tree_nodes readonly
as
begin

	set nocount on

-- @result
	;with paths(node_id, node)
	as (  
		select node_id, cast(concat('/', c.num, '/') as hierarchyid) as node
		from @nodes c
		where parent_id is null

		union all   
		select c.node_id, cast(concat(p.node.ToString(), c.num, '/') as hierarchyid)
		from @nodes as c
			join paths as p on c.parent_id = p.node_id
		)  
		select 
			x.NODE_ID,
			x.PARENT_ID,
			x.NUM,
			P.NODE,
			LEVEL_ID = p.node.GetLevel()
		from @nodes x
			join paths p on p.node_id = x.node_id

end
GO
