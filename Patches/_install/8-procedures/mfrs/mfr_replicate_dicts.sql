if object_id('mfr_replicate_dicts') is not null drop proc mfr_replicate_dicts
go
create proc mfr_replicate_dicts
	@subjectId int
as
begin
	-- AGENTS
		insert into agents(name, name_print, inn)
		select distinct agent_name, agent_name, '-'
		from #sdocs
		where agent_name not in (select name from agents)
			and agent_name != '-'

		update x
		set agent_id = isnull(a.main_id, a.agent_id)
		from #sdocs x
			join agents a on a.name = x.agent_name

	-- PRODUCTS
		-- @products
			declare @products table(extern_id varchar(32), name varchar(500))
			
			insert into @products(extern_id, name)
			select extern_id, name = min(name)
			from (
				select extern_id = extern_product_id, name = min(product_name) from #sdocs_products group by extern_product_id
				union select extern_product_id, min(product_name) from #sdocs_contents group by extern_product_id
				union select extern_item_id, min(item_name) from #sdocs_contents group by extern_item_id
				) u
			group by extern_id

		-- нормализация имён
			update x set
				name = xx.name
			from mfr_replications_products x
				join @products xx on xx.extern_id = x.extern_id
			where x.name != xx.name

			update p set p.name = r.name
			from mfr_replications_products r
				join products p on p.product_id = r.product_id
			where r.name != p.name

		-- auto-insert
			-- пополняем mapping
			insert into mfr_replications_products(extern_id, name)
			select x.extern_id, x.name
			from @products x
			where not exists(select 1 from mfr_replications_products where extern_id = x.extern_id)

			update r set product_id = p.product_id
			from mfr_replications_products r
				join products p on p.name = r.name
			where r.product_id is null

			-- пополняем справочник
			insert into products(name, name_print, status_id)
			select distinct name, name, 5
			from mfr_replications_products x
			where product_id is null
                and not exists(select 1 from products where name = x.name)

			-- завершаем mapping
			update x set product_id = p.product_id
			from mfr_replications_products x
				join products p on p.name = x.name
			where x.product_id is null

		-- back updates
			update x set product_id = isnull(pp.main_id, pp.product_id)
			from #sdocs_products x
				join mfr_replications_products p on p.extern_id = x.extern_product_id
					join products pp on pp.product_id = p.product_id
			where x.product_id is null

			update x set product_id = isnull(pp.main_id, pp.product_id)
			from #sdocs_contents x
				join mfr_replications_products p on p.extern_id = x.extern_product_id
					join products pp on pp.product_id = p.product_id
			where x.product_id is null

			update x set item_id = isnull(pp.main_id, pp.product_id)
			from #sdocs_contents x
				join mfr_replications_products p on p.extern_id = x.extern_item_id
					join products pp on pp.product_id = p.product_id

	declare @seed_id int

	-- UNITS
		-- auto-insert
			set @seed_id = isnull((select max(unit_id) from products_units), 0)
			insert into products_units(unit_id, name)
			select @seed_id + (row_number() over (order by unit_name)), u.unit_name
			from (
				select distinct x.unit_name
				from #sdocs_products x
				where not exists(select 1 from products_units where name = x.unit_name)
				) u

		-- back updates
			update x set unit_id = u.unit_id
			from #sdocs_products x
				join products_units u on u.name = x.unit_name

        -- default unit_id
            update x set unit_id = u.unit_id
            from products x
                join (
                    select item_id, min(unit_name) as unit_name
                    from #sdocs_contents
                    group by item_id
                ) c on c.item_id = x.product_id
                join products_units u on u.name = c.unit_name
            where x.unit_id is null

	-- MFR_ATTRS
		if not exists(select 1 from mfr_attrs where attr_key = 'MfrRoute')
			insert into mfr_attrs(slice, group_key, group_name, attr_key, name)
			values ('Base', 'Misc', 'Прочие', 'MfrRoute', 'Маршрут')

		declare @attrs table(row_id int identity primary key, attr_id int, name varchar(150))
			insert into @attrs(name)
			select distinct attr_name
			from #sdocs_contents_attrs x
			where not exists(
				select 1 from mfr_attrs where group_key = 'AttrItems' and name = x.attr_name
				)

		set @seed_id = isnull((select max(attr_id) from mfr_attrs), 0)
		update x
		set attr_id = @seed_id + number_id
		from @attrs x
			join (
				select row_id, row_number() over (order by row_id) as number_id
				from @attrs
			) xx on xx.row_id = x.row_id

		insert into mfr_attrs(slice, group_name, group_key, attr_key, name, value_type)
		select 'content', 'АтрибутыДеталей', 'AttrItems', concat('AttrItem', attr_id), name, 'list'
		from @attrs

		update x set attr_id = a.attr_id
		from #sdocs_contents_attrs x
			join mfr_attrs a on a.group_key = 'AttrItems' and a.name = x.attr_name

	-- MFR_PLACES
		insert into mfr_places(subject_id, name, full_name)
		select distinct @subjectId, place_name, place_name from #sdocs_opers x
		where not exists(select 1 from mfr_places where name = x.place_name)

		update x set place_id = xx.place_id
		from #sdocs_opers x
			join mfr_places xx on xx.name = x.place_name

	-- MOLS_POSTS
		insert into mols_posts(subject_id, name, extern_id, rate_price)
		select @subjectid, post_name, max(post_extern_id), max(rate_price) from #sdocs_opers x
		where not exists(select 1 from mols_posts where name = x.post_name)
			and not exists(select 1 from mols_posts where extern_id = x.post_extern_id)
		group by post_name

		update x set post_id = xx.post_id
		from #sdocs_opers x
			join mols_posts xx on xx.subject_id = @subjectid and xx.extern_id = x.post_extern_id

		update x set post_id = xx.post_id
		from #sdocs_opers x
			join mols_posts xx on xx.subject_id = @subjectid and xx.name = x.post_name
		where x.post_id is null

	-- MFR_RESOURCES
		insert into mfr_resources(name, extern_id)
		select resource_name, max(resource_extern_id)
		from #sdocs_opers x
		where isnull(resource_name,'') != ''
			and not exists(select 1 from mfr_resources where name = x.resource_name)
			and not exists(select 1 from mfr_resources where extern_id = x.resource_extern_id)
		group by resource_name

		update x set resource_id = xx.resource_id
		from #sdocs_opers x
			join mfr_resources xx on xx.extern_id = x.resource_extern_id

		update x set resource_id = xx.resource_id
		from #sdocs_opers x
			join mfr_resources xx on xx.name = x.resource_name
		where x.resource_id is null

end
GO
