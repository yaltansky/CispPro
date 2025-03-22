if object_id('invoices_create_supplies') is not null drop proc invoices_create_supplies
go
create proc invoices_create_supplies
	@mol_id int,
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

	declare @today datetime = dbo.today()	

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids
		if @queue_id is null
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'inv')
		else
			insert into @buffer select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'inv'

	exec invoices_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

BEGIN TRY
BEGIN TRANSACTION
	declare @map as app_mapids

	-- sdocs
		-- print dbo.sys_query_insert('sdocs', 'type_id,status_id,add_mol_id,add_date', 'doc_id' ,'x', 0)
		insert into sdocs(
			parent_id, type_id, status_id, 
			acc_register_id, invoice_id, subject_id, d_doc, d_delivery, agent_id, agent_dogovor, mol_id, ccy_id, ccy_rate, value_ccy, value_rur, note, add_mol_id, add_date, dogovor_number, dogovor_date, spec_number, spec_date
			)
			output inserted.parent_id, inserted.doc_id into @map
		select
			x.doc_id, 9, 0, 
			acc_register_id, doc_id, subject_id, @today, d_delivery, agent_id, agent_dogovor, @mol_id, ccy_id, ccy_rate, value_ccy, value_rur, note, @mol_id, getdate(), dogovor_number, dogovor_date, spec_number, spec_date
		FROM sdocs x
			join @buffer buf on buf.id = x.doc_id
		
		update x set 
			number = concat(s.short_name, '/ПСТ/', x.doc_id),
			refkey = concat('/sdocs/', doc_id) 
		from sdocs x
			join subjects s on s.subject_id = x.subject_id
		where x.doc_id in (select new_id from @map)

	-- sdocs_products
		-- print dbo.sys_query_insert('sdocs_products', '', 'id' ,'x', 0)
		insert into sdocs_products(
			errors, doc_id, product_id, quantity, w_netto, w_brutto, unit_id, price, price_pure, price_pure_trf, nds_ratio, value_pure, value_nds, value_ccy, value_rur, note, value_work, price_list, mfr_number, plan_q, due_date, has_details
			)
		select 
			detail_id, m.new_id, product_id, quantity, w_netto, w_brutto, unit_id, price, price_pure, price_pure_trf, nds_ratio, value_pure, value_nds, value_ccy, value_rur, note, value_work, price_list, mfr_number, plan_q, due_date, has_details
		from sdocs_products x
			join @map m on m.id = x.doc_id
		order by x.doc_id, x.detail_id

		-- print dbo.sys_query_insert('sdocs_products_details', '', 'id' ,'x', 0)
        insert into sdocs_products_details(
            detail_id, doc_id, mfr_number, note, quantity, stock_addr_id, add_date, add_mol_id)
        select 
            sp.detail_id, m.new_id, x.mfr_number, x.note, x.quantity, x.stock_addr_id, getdate(), @mol_id
        from sdocs_products_details x
            join @map m on m.id = x.doc_id
            join sdocs_products sp on sp.doc_id = m.new_id and cast(sp.errors as int) = x.detail_id

	-- results
		exec objs_buffer_clear @mol_id, 'sd'
		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'sd', new_id, @mol_id from @map

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH -- TRANSACTION

end
go
