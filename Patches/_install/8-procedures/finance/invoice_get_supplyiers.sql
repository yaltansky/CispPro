if object_id('invoice_get_supplyiers') is not null drop proc invoice_get_supplyiers
go
-- exec invoice_get_supplyiers 27340
create proc invoice_get_supplyiers
	@product_id int,
	@search varchar(100) = null,
	@show_all bit = 0
as
begin

	set nocount on;

	set @search = '%' + @search + '%'

	declare @supplyiers as app_pkids

	if @show_all = 0
		insert into @supplyiers 
		select distinct i.agent_id from supply_invoices_products p
			join supply_invoices i on i.doc_id = p.doc_id
		where p.product_id = @product_id

	select top 50 AGENT_ID, NAME
	from agents x
	where (@search is null or name like @search)
		and (
			@show_all = 1
			or agent_id in (select id from @supplyiers)
		)
	order by x.name

end
go
