if object_id('mfr_replicate_products') is not null drop proc mfr_replicate_products
go
create proc mfr_replicate_products
	@ids as app_pkids readonly,
	@note varchar(100) = null
as
begin
	set nocount on;

    -- RAISERROR('The procedure mfr_replicate_products is temporarily turned off.', 16, 1)
    -- return

    if db_name() = 'CISP_REM'
        return -- excluded

	declare @subjectId int = cast((select dbo.app_registry_value('MfrReplSubjectId')) as int)
	if @subjectId is null
	begin
		raiserror('MfrReplSubjectId option is not defined for database.', 16, 1)
		return
	end

	declare @branchName varchar(20) = dbo.app_registry_varchar('MfrReplProductsBranchName')
	if @branchName is null
	begin
		raiserror('MfrReplProductsBranchName option is not defined for database.', 16, 1)
		return
	end

    declare @ItemPrefix varchar(20) = 
        case
            when db_name() != 'CISP' then concat(@subjectId, '-') else ''
        end

	-- @products
		declare @products table(
            extern_id varchar(32) primary key,
            code varchar(32) index ix_code,
            name varchar(500),
            unit_name varchar(30)
            )
		
		insert into @products(
            extern_id, code, name, unit_name
            )
		select 
			concat(@ItemPrefix, ItemId),
			ItemId,
			ItemName,
			UnitName
		from cisp_gate..products
		where BranchName = @branchName
			and (not exists(select 1 from @ids)
				or itemid in (select id from @ids)
				)
			and ProcessedOn is null

        if not exists(select 1 from @products)
        begin
            print 'mfr_replicate_products: nothing todo.';
            return
        end

	-- нормализация имён
        update x set
            name = xx.name
        from mfr_replications_products x
            join @products xx on xx.extern_id = x.extern_id
        where x.name != xx.name

        update p set name = r.name, name_print = r.name
        from products p
            join mfr_replications_products r on r.product_id = p.product_id
        where p.name != r.name

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

	-- products_units
		declare @seed_id int = isnull((select max(unit_id) from products_units), 0)
		insert into products_units(unit_id, name)
		select 
			@seed_id + (row_number() over (order by name)),
			name
		from (
			select distinct name = unitname
			from cisp_gate..products x
			where branchname = @branchName
				and isnull(unitname, '') != ''
				and not exists(select 1 from products_units where name = x.unitname)
			) u
			
        -- update default unit_id
        update p set unit_id = u.unit_id
        from mfr_replications_products rp
            join cisp_gate..products gp on gp.ItemName = rp.name
                join products_units u on u.name = gp.UnitName
            join products p on p.product_id = rp.product_id
        where p.unit_id is null
            and gp.UnitName is not null        

		-- products
		insert into products(name, name_print, inner_number, status_id, unit_id)
		select distinct x.name, x.name, p.code, 5, u.unit_id
		from mfr_replications_products x
            join @products p on p.extern_id = x.extern_id
			left join products_units u on u.name = p.unit_name
		where x.product_id is null
            and not exists(select 1 from products where name = x.name)

        -- завершаем mapping
        update x set product_id = p.product_id
        from mfr_replications_products x
            join products p on p.name = x.name
        where x.product_id is null

		-- products_ukoefs
		insert into products_ukoefs(product_id, unit_from, unit_to, koef)
		select distinct product_id, unit_from, unit_to, koef 
		from (
			select 
				r.product_id, 
				unit_from = lower(rtrim(ltrim(u.UnitFrom))),
				unit_to = lower(rtrim(ltrim(u.UnitTo))), 
				u.koef
			from mfr_replications_products r
				join cisp_gate..products_units u on concat(@ItemPrefix, ProductId) = r.extern_id
			) x
		where not exists(select 1 from products_ukoefs where product_id = x.product_id and unit_from = x.unit_from and unit_to = x.unit_to)

	-- set ProcessedOn
	update cisp_gate..products set ProcessedOn = getdate()
	where BranchName = @branchName
		and ItemId in (select code from @products)

end
GO
