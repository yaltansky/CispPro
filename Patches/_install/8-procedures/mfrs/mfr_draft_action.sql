if object_id('mfr_draft_action') is not null drop proc mfr_draft_action
go
create proc mfr_draft_action
	@mol_id int,
	@draft_id int,
	@action varchar(32)
as
begin

	set nocount on;	

	declare @mfr_doc_id int, @product_id int, @item_id int

		select 
			@mfr_doc_id = mfr_doc_id,
			@product_id = product_id,
			@item_id = item_id
		from mfr_drafts 
		where draft_id = @draft_id and mfr_doc_id != 0

	if @action = 'MakeRoot'
	begin
		delete x from mfr_drafts_items x
			join mfr_drafts d on d.draft_id = x.draft_id
		where d.mfr_doc_id = @mfr_doc_id
			and x.item_id = @item_id

		update mfr_drafts set 
			is_root = 1,
			product_id = @product_id
		where draft_id = @draft_id
	end

	else if @action = 'MakePrimary'
	begin
		update mfr_drafts set is_product = 0 where mfr_doc_id = @mfr_doc_id and product_id = @product_id
		update mfr_drafts set is_product = 1 where draft_id = @draft_id and product_id = @product_id
	end

	else if @action = 'MergeRoots'
	begin
		declare @new_root_id int = (select draft_id from mfr_drafts where mfr_doc_id = @mfr_doc_id and is_deleted = 0 and item_id = @product_id)
		if @new_root_id is not null
		begin
			raiserror('В реестре тех. выписок уже есть головная деталь. Автоматическое объединение узлов верхнего уровня невозможно.', 16, 1)
			return
		end

		-- create new root
			declare @roots table(draft_id int primary key, product_id int)

			insert into mfr_drafts(mfr_doc_id, product_id, item_id, is_buy, work_type_1, d_doc, number, status_id, note)
			output inserted.draft_id, inserted.product_id into @roots
			select sp.doc_id, sp.product_id, sp.product_id, 0, 1, sd.d_doc, '-', 10, 'авто-объединение узлов верхнего уровня'
			from sdocs_products sp
				join sdocs sd on sd.doc_id = sp.doc_id
			where sd.doc_id = @mfr_doc_id

		-- add opers
			insert into mfr_drafts_opers(draft_id, number, name, duration, duration_id)
			select draft_id, 1, 'Контроль', 1, 2
			from @roots

		-- add items
			insert into mfr_drafts_items(draft_id, item_id, q_brutto, unit_name)
			select r.draft_id, d.item_id, 1, 'шт'
			from @roots r
				join mfr_drafts d on d.mfr_doc_id = @mfr_doc_id and d.product_id = r.product_id
			where is_root = 1
				and is_deleted = 0

		-- clear is_root
			update mfr_drafts set is_root = 0, IS_PRODUCT = 0 where mfr_doc_id = @mfr_doc_id
			update mfr_drafts set is_root = 1, is_product = 1 where draft_id in (select draft_id from @roots)

		-- calc contents
			exec mfr_drafts_calc 1000, @doc_id = @mfr_doc_id

	end
end
go
