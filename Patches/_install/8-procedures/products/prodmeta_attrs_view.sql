if object_id('prodmeta_attrs_view') is not null drop proc prodmeta_attrs_view
go
-- exec prodmeta_attrs_view @mol_id = 700, @extra_id = 2
create proc prodmeta_attrs_view
	@mol_id int,
	@class_id int = null,
	@parent_id int = null,
	@search varchar(max) = null,
	@extra_id int = null
		-- 1 show used only
		-- 2 show by query
		-- 99 use products from PP-buffer
as
begin

	set nocount on;
    
	set @search = '%' + @search + '%'

	declare @result table (
		attr_id int primary key,
		node hierarchyid
		)

	if @parent_id is not null
		insert into @result(attr_id)
		select attr_id
		from prodmeta_attrs
		where parent_id = @parent_id
	
	else begin

		if @search is not null 
			insert into @result(attr_id, node)
			select a.attr_id, a.node
			from prodmeta_attrs a
			where (
				a.name like @search
				or a.code like @search
				or a.note like @search
				)

		else begin
			declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
			declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'PP')
			declare @allproducts bit = case when exists(select 1 from @buffer where id = -1) then 1 else 0 end

			insert into @result(attr_id, node)
			select attr_id, node
			from prodmeta_attrs
			where is_deleted = 0
				and (
					@extra_id is null
					or (
						@extra_id = 99
						and attr_id in (
							select distinct attr_id from products_attrs
							where @allproducts = 1
								or product_id in (select id from @buffer)
						)
					)
				)
		end

		if @extra_id = 1
			delete from @result
			where attr_id not in (select attr_id from products_attrs)
		
		-- apply @class_id
		if @class_id is not null
		begin
			declare @restricted as app_pkids
				insert into @restricted
				select attr_id from prodmeta_classes_attrs where class_id = @class_id

			if exists(select 1 from @restricted)
				delete x from @result x
				where not exists(select 1 from @restricted where id = x.attr_id)
		end

		-- add parents
		insert into @result(attr_id, node)
		select distinct x.attr_id, x.node
		from prodmeta_attrs x
			join @result r on r.node.IsDescendantOf(x.node) = 1
		where x.has_childs = 1
			and x.is_deleted = 0
			and not exists(select 1 from @result where attr_id = x.attr_id)
	end

-- final
	select a.*
        , node_id = a.attr_id
	from prodmeta_attrs a
		join @result r on r.attr_id	= a.attr_id
	order by a.node
end
GO
