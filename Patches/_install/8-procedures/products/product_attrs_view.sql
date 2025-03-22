if object_id('product_attrs_view') is not null drop proc product_attrs_view
go
-- exec product_attrs_view @product_id = 337
create proc product_attrs_view
	@product_id int,
	@extra_id int = null,
		-- 1 - show all
	@search varchar(max) = null,
    @trace bit = 0
as
begin

	set nocount on;

	set @search = '%' + @search + '%'

	declare @result table(
		attr_id int index ix_attr,
		id int,
		attr_value_id int,
		attr_value nvarchar(max),
		attr_value_note nvarchar(max),
		node hierarchyid
		)

	if @search is not null
		insert into @result(attr_id, node, id, attr_value_id, attr_value, attr_value_note)
		select a.attr_id, a.node, x.id, x.attr_value_id, x.attr_value, x.attr_value_note
		from prodmeta_attrs a
            left join products_attrs x on x.product_id = @product_id and x.attr_id = a.attr_id
		where (
				(@extra_id is null and x.id is not null)
				or (@extra_id = 1)
				)
			and (
				a.name like @search
				or a.code like @search
				or x.attr_value like @search
				)
			and (x.is_deleted = 0 or @extra_id = 1)

	else begin
		
		insert into @result(attr_id, node, id, attr_value_id, attr_value, attr_value_note)
		select a.attr_id, a.node, x.id, x.attr_value_id, x.attr_value, x.attr_value_note
		from prodmeta_attrs a
			left join products_attrs x on x.product_id = @product_id and x.attr_id = a.attr_id
		where a.is_deleted = 0
			and (
				(@extra_id is null and x.id is not null)
				or (@extra_id = 1)
				)
			and (x.is_deleted = 0 or @extra_id = 1)
	end

	insert into @result(attr_id, node)
	select distinct x.attr_id, x.node
	from prodmeta_attrs x
		join @result r on r.node.IsDescendantOf(x.node) = 1
	where x.has_childs = 1
		and x.is_deleted = 0
		and not exists(select 1 from @result where attr_id = x.attr_id)

-- select & drop
	select
		product_id = @product_id,
		r.id,
		a.parent_id,
		a.attr_id,
		a.name,				
		a.has_childs,		
		attr_code = a.code,
		r.attr_value_id,
		r.attr_value,
		r.attr_value_note,
		attr_value_type = a.value_type
	from @result r
		join prodmeta_attrs a on a.attr_id = r.attr_id
	order by r.node
end
GO
