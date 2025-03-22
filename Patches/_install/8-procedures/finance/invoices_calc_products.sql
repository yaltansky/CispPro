if object_id('invoices_calc_products') is not null drop proc invoices_calc_products
go
create proc invoices_calc_products
	@mol_id int = null,
	@trace bit = 0
as
begin

	set nocount on;

	declare @prices table(
		row_id int identity primary key,
		product_id int,
		doc_id int, d_doc datetime, price_rur float,
		supplier_id int,
		manager_id int,		
		sort_id int,
		is_last bit,
		index ix_product(product_id,row_id),
		index ix_sort(product_id,sort_id)
		)
		
	insert into @prices(product_id, doc_id, d_doc, price_rur, supplier_id, manager_id)
	select p.product_id, i.doc_id, i.d_doc, p.value_rur / nullif(p.quantity,0), i.agent_id, i.mol_id
	from supply_invoices i
		join supply_invoices_products p on p.doc_id = i.doc_id

	update x set sort_id = xx.sort_id
	from @prices x
		join (
			select
				row_id,
				sort_id = row_number() over (partition by product_id order by row_id)
			from @prices
		) xx on xx.row_id = x.row_id

	delete from @prices where sort_id > 3

	declare @prices_final table(
		product_id int primary key,
		min_price_rur float,
		last_doc_id int, 
		last_d_doc datetime,
		last_supplier_id int,
		last_manager_id int
		)

	;with 
		last_prices_sort as (
			select product_id, last_sort_id = max(sort_id)
			from @prices
			group by product_id			
		),
		last_prices as (
			select p.product_id, p.supplier_id, p.manager_id, p.doc_id
			from @prices p
				join last_prices_sort ls on ls.product_id = p.product_id and ls.last_sort_id = p.sort_id
		)
		insert into @prices_final(product_id, min_price_rur, last_doc_id, last_d_doc, last_supplier_id, last_manager_id)
		select x.product_id, min(x.price_rur), max(lp.doc_id), max(x.d_doc), max(lp.supplier_id), max(lp.manager_id)
		from @prices x
			join last_prices lp on lp.product_id = x.product_id
		group by x.product_id

	delete x from products_attrs x
		join @prices_final pr on pr.product_id = x.product_id
	where x.attr_id in (
		select attr_id from prodmeta_attrs
		where name like 'закупка.%'
			and name not in ('закупка.КодМенеджера')
		)

	declare @attr_id int 
	
	set @attr_id = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.Цена')
		insert into products_attrs(product_id, attr_id, attr_value, attr_value_number)
		select product_id, @attr_id, ltrim(str(min_price_rur, 25, 2)), min_price_rur
		from @prices_final

	set @attr_id = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.Дата')
		insert into products_attrs(product_id, attr_id, attr_value)
		select product_id, @attr_id, convert(varchar, last_d_doc, 104)
		from @prices_final

	set @attr_id = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.КодСчёта')
		insert into products_attrs(product_id, attr_id, attr_value)
		select product_id, @attr_id, last_doc_id
		from @prices_final

	set @attr_id = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.КодПоставщика')
		insert into products_attrs(product_id, attr_id, attr_value)
		select x.product_id, @attr_id, x.last_supplier_id
		from @prices_final x

end
GO
