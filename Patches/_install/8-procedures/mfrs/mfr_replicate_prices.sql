if object_id('mfr_replicate_prices') is not null drop proc mfr_replicate_prices
go
create proc mfr_replicate_prices
as
begin

	set nocount on;

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

    truncate table mfr_items_prices

    -- import
    if object_id('cisp_gate.dbo.prices') is not null
    begin
        insert into mfr_items_prices(product_id, unit_id, price_pure, price)
        select pr.product_id, u.unit_id, p.pc, isnull(nullif(p.pct,0), p.pc * 1.2)
        from cisp_gate..prices p
            join (
                select productid, packid = max(packid)
                from cisp_gate..prices where branchname = @branchName
                group by productid
            ) lst on lst.packid = p.packid and lst.productid = p.productid
            join products_units u on u.name = p.unitname
            join mfr_replications_products pr on pr.extern_id = concat(@subjectId, '-', p.productid)
        where p.pc > 0;
    end;

    -- calc by supply
        declare @prices table(product_id int primary key, unit_id int, price_pure float, price float)

        update sdocs set ccy_id = 'RUR' where type_id in (8,9) and ccy_id is null

        insert into @prices(product_id, unit_id, price_pure, price)
        select
            d.product_id,
            d.unit_id,
            isnull(cr.rate,1) * d.price_pure * case when d.unit_id in (38,45) then 0.001 else 1 end,
            isnull(cr.rate,1) * d.price * case when d.unit_id in (38,45) then 0.001 else 1 end
        from sdocs_products d
            join sdocs h on d.doc_id = h.doc_id
            left join ccy_rates_cross cr on cr.d_doc = h.d_doc and cr.from_ccy_id = h.ccy_id and cr.to_ccy_id = 'rur'
            join (
                select d.product_id, detail_id = max(d.detail_id)
                from sdocs_products d
                    join sdocs h on d.doc_id = h.doc_id
                        join (
                            select d.product_id, d_doc = max(h.d_doc)
                            from sdocs_products d
                                join sdocs h on d.doc_id = h.doc_id
                            where h.type_id in (8,9)
                                and h.status_id >= 0
                                and isnull(d.price,0) > 0.001
                            group by d.product_id
                        ) dd on dd.product_id = d.product_id and dd.d_doc = h.d_doc
                where h.type_id in (8,9)
                    and h.status_id >= 0                    
                group by d.product_id
            ) s on (d.detail_id = s.detail_id)
        where d.product_id is not null
            and isnull(d.price,0) > 0.001

        -- replace
        delete from mfr_items_prices where product_id in (select product_id from @prices)

        insert into mfr_items_prices(product_id, unit_id, price_pure, price)
        select product_id, unit_id, price_pure, price from @prices

    -- sync 'закупка.КодПоставщика'
        declare @ships table(
            row_id int identity primary key,
            product_id int,
            doc_id int, d_doc date, 
            supplier_id int,
            price_rur float,
            value_rur float,
            sort_id int
            )
            
        insert into @ships(product_id, doc_id, d_doc, supplier_id, price_rur, value_rur)
        select p.product_id, i.doc_id, i.d_doc, i.agent_id,
            p.value_rur / nullif(p.quantity,0),
            p.value_rur
        from sdocs i
            join sdocs_products p on p.doc_id = i.doc_id
        where i.type_id = 9 -- приходы
            and i.agent_id is not null
            and i.value_rur > 0

        update x set sort_id = xx.sort_id
        from @ships x
            join (
                select
                    row_id,
                    sort_id = row_number() over (partition by product_id order by value_rur desc)
                from @ships
            ) xx on xx.row_id = x.row_id

        delete from @ships where sort_id > 1

        delete x from products_attrs x
            join @ships pr on pr.product_id = x.product_id
        where attr_id in (
                select attr_id from prodmeta_attrs
                where name = 'закупка.КодПоставщика'
                )

        declare @attr_id int 
        
        set @attr_id = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.КодПоставщика')
            insert into products_attrs(product_id, attr_id, attr_value)
            select product_id, @attr_id, supplier_id
            from @ships x

end
go
