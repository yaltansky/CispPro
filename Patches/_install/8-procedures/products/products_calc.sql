if object_id('products_calc') is not null drop proc products_calc
go
create proc products_calc
	@mol_id int = null
as
begin

	set nocount on;
	SET XACT_ABORT ON;

-- авто-архивирование дубликатов
	update products
	set status_id = 10
	where status_id <> 10
		and main_id is not null

-- sdocs_products
	update x set product_id = p.main_id
	from sdocs_products x
		join products p on p.product_id = x.product_id
		join sdocs sd on sd.doc_id = x.doc_id
	where sd.type_id <> 5 -- кроме производственных заказов
		and p.main_id is not null

end
GO
