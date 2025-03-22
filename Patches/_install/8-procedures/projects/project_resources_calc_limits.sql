if object_id('project_resources_calc_limits') is not null drop proc project_resources_calc_limits
go
create proc project_resources_calc_limits
	@mol_id int,
	@tree_id int,
	@resource_id int = null,
	@d_from datetime = null,
	@d_to  datetime = null
as
begin

	set nocount on;

	declare @projects table(project_id int)
	declare @node hierarchyid; select @node = node from trees where tree_id = @tree_id
	insert into @projects select obj_id from trees where node.IsDescendantOf(@node) = 1 and obj_type = 'PRJ' and obj_id is not null

	delete from projects_resources_az_limits where tree_id = @tree_id
		and (@resource_id is null or resource_id = @resource_id)
		and (@d_from is null or d_doc >= @d_from)
		and (@d_to is null or d_doc <= @d_to)

	insert into projects_resources_az_limits (
		tree_id, resource_id, d_doc, limit_q, quantity
		)
	select
		isnull(@tree_id,0)
		, fd.resource_id, fd.d_doc
		, max(a.limit_q)
		, sum(fd.quantity)
	from projects_resources_charts fd
		inner join projects_resources_limits a on a.resource_id = fd.resource_id
	where fd.project_id in (select project_id from @projects)
		and a.tree_id = @tree_id
		and (@resource_id is null or fd.resource_id = @resource_id)
		and (@d_from is null or fd.d_doc >= @d_from)
		and (@d_to is null or fd.d_doc <= @d_to)
		and a.limit_q is not null
	group by fd.resource_id, fd.d_doc

-- auto-insert
	insert into projects_resources_limits(tree_id, resource_id, price, limit_q)
	select distinct x.tree_id, x.resource_id, 0, 0
	from projects_resources_az_tasks x
	where x.tree_id = @tree_id
		and not exists(select 1 from projects_resources_limits where tree_id = x.tree_id and resource_id = x.resource_id)

end
go
