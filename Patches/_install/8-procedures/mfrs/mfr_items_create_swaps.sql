if object_id('mfr_items_create_swaps') is not null drop proc mfr_items_create_swaps
go
-- exec mfr_items_create_swaps 1000
create proc mfr_items_create_swaps
	@mol_id int,
	@new_item_id int,
	@new_unit_id int,
	@k_prop float = 1,
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

	declare @proc_name varchar(100) = object_name(@@procid)
	
	declare @today date = dbo.today()
	declare @buffer as app_pkids
	
	if @queue_id is null
		insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
	else
		insert into @buffer select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfc'

    declare @action varchar(32)
        if exists(
            select 1 from sdocs_mfr_contents c
                join @buffer i on i.id = c.mfr_doc_id
                join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id and isnull(mfr.acc_register_id,0) != 0
            ) set @action = 'admin'
    exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action
    if @@error != 0 return

	BEGIN TRY
	BEGIN TRANSACTION

		declare @swaps as app_pkids

		declare @subject_id int = (
			select top 1 sd.subject_id from sdocs_mfr_contents c
				join sdocs sd on sd.doc_id = c.mfr_doc_id
			where content_id in (select id from @buffer)
			)

		insert into mfr_swaps(type_id, subject_id, d_doc, status_id, note, add_mol_id)
			output inserted.doc_id into @swaps
		select 11, @subject_id, @today, 0, '#bycontents', @mol_id

		insert into mfr_swaps_products(doc_id, mfr_number, product_id, unit_id, quantity, dest_product_id, dest_unit_id, dest_quantity)
		select sw.id, mfr.number, c.item_id, u.unit_id,
            (r.q_mfr - r.q_job), 
			@new_item_id, 
			isnull(@new_unit_id, u.unit_id),
			@k_prop * (r.q_mfr - r.q_job)
		from @swaps sw, sdocs_mfr_contents c
			join @buffer i on i.id = c.content_id
			join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id
			join products_units u on u.name = c.unit_name
            join (
                select id_mfr, q_mfr = sum(q_mfr), q_job = isnull(sum(q_lzk), 0) + isnull(sum(q_job), 0)
                from mfr_r_provides
                group by id_mfr
            ) r on r.id_mfr = c.content_id
        where (r.q_mfr - r.q_job) > 0

        delete x from sdocs x
            join @swaps i on i.id = x.doc_id
        where not exists(
            select 1 from sdocs_products where doc_id = x.doc_id
            )

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

end
go
