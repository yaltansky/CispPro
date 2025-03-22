if object_id('sdocs_stocks_addrs_buffer_action') is not null drop proc sdocs_stocks_addrs_buffer_action
go
create proc sdocs_stocks_addrs_buffer_action
	@mol_id int,
	@action varchar(32)
as
begin
    set nocount on;

	declare @proc_name varchar(50) = object_name(@@procid)
	-- exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'
    if @@error != 0 return
	
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'addr')
	declare @buffer_products as app_pkids; insert into @buffer_products select id from dbo.objs_buffer(@mol_id, 'p')

	if @action = 'viewProducts'
    begin
        exec objs_buffer_clear @mol_id, 'P'

        insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
        select distinct @buffer_id, 'P', x.product_id, @mol_id
        from sdocs_stocks_products x
            join @buffer b on b.id = x.addr_id
    end

	else if @action = 'addProducts'
        insert into sdocs_stocks_products(stock_id, addr_id, product_id, add_mol_id)
        select a.stock_id, b.id, p.id, @mol_id
        from @buffer b, @buffer_products p, sdocs_stocks_addrs a
        where a.addr_id = b.id
            and not exists(select 1 from sdocs_stocks_products where addr_id = b.id and product_id = p.id)

	else if @action = 'removeProducts'
        delete x from sdocs_stocks_products x
            join @buffer b on b.id = x.addr_id
            join @buffer_products p on p.id = x.product_id
end
go
