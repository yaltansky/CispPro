if exists(select 1 from sys.objects where name = 'trees_search')
	drop proc trees_search
go

create proc trees_search
	@type_id int = 1,
	@tree_id int = null,
	@search varchar(32) = null,
	@show_leafs bit = 1,
	@ids varchar(max)
as
begin

	set nocount on;

	declare @result table(tree_id int, node hierarchyid)

	if @tree_id is not null
	begin
		declare @node hierarchyid = (select node from trees where tree_id = @tree_id)
		insert into @result(tree_id)
			select tree_id from trees
			where type_id = @type_id
				and obj_id is not null
				and node.IsDescendantOf(@node) = 1
				and (@show_leafs = 1 or has_childs = 1)
	end

	else
	begin
		set @search = '%' + @search + '%'

		declare @objs table(obj_id int)
		if @ids is not null
			insert into @objs select distinct item from dbo.str2rows(@ids, ',')

		-- search
		insert into @result(tree_id, node)
			select tree_id, node from trees
			where type_id = @type_id
				and (@search is null or name like @search)
				and (@show_leafs = 1 or has_childs = 1)
				and (@ids is null or obj_id in (select obj_id from @objs))
			
		-- + parents	
		insert into @result(tree_id, node)
			select distinct x.tree_id, x.node
			from trees x
				join @result r on r.node.IsDescendantOf(x.node) = 1
			where x.type_id = @type_id
				and x.has_childs = 1
	end

	-- return results
	select * from trees
	where tree_id in (select tree_id from @result)
	order by sort_id

end
GO
