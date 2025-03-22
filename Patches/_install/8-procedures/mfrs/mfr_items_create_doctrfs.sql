if object_id('mfr_items_create_doctrfs') is not null drop proc mfr_items_create_doctrfs
go
-- exec mfr_items_create_doctrfs 1000, 127
create proc mfr_items_create_doctrfs
	@mol_id int,
	@subject_id int,
	@d_doc date = null,
	@place_id int = null,
	@place_to_id int = null,
	@place_mol_id int = null,
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

	declare @proc_name varchar(100) = object_name(@@procid)
	exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name
    if @@error != 0 return

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids
	
	if @queue_id is null
		insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
	else
		insert into @buffer select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfc'

	declare @details table(
		item_id int,
		mfr_number varchar(100),
		unit_id int,
		quantity float
		)

	set @d_doc = isnull(@d_doc, dbo.today())
	if @subject_id is null set @subject_id = (select top 1 subject_id from mfr_plans where status_id = 1)
	
	-- @details
		insert into @details(item_id, mfr_number, unit_id, quantity)
		select x.item_id, mfr.number, unit_id, sum(q_brutto_product)
		from sdocs_mfr_contents x
			join @buffer i on i.id = x.content_id
			join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id
			join products_units u on u.name = x.unit_name
		group by 
			x.item_id, mfr.number, unit_id

		if not exists(select 1 from @details)
		begin
			raiserror('Нет деталей для создания документов "Передаточная накладная".', 16, 1)
			return
		end

	BEGIN TRY
	BEGIN TRANSACTION
		
		declare @docs table(doc_id int primary key)
			
		-- sdocs			
			insert into sdocs(
				type_id, subject_id, d_doc,
				status_id, place_id, place_to_id,
				mol_id, add_date, add_mol_id
				)
			output inserted.doc_id into @docs
			select 
				10, @subject_id, @d_doc, 
				0, @place_id, @place_to_id,
				@place_mol_id, getdate(), @mol_id

			update x set number = concat(sbj.short_name, '/ДЕТ-', x.doc_id)
			from sdocs x
				join @docs i on i.doc_id = x.doc_id
				join subjects sbj on sbj.subject_id = x.subject_id

		-- sdocs_products
			insert into sdocs_products(doc_id, product_id, mfr_number, unit_id, plan_q, quantity)
			select d.doc_id, x.item_id, x.mfr_number, x.unit_id, x.quantity, x.quantity
			from @details x
				cross apply @docs d
				join products p on p.product_id = x.item_id
			order by p.name

		-- results
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'MFTRF'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'MFTRF', doc_id, @mol_id from @docs

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

end
go
