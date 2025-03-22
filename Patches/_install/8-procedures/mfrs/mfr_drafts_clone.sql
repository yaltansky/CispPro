if object_id('mfr_drafts_clone') is not null drop proc mfr_drafts_clone
go
create proc mfr_drafts_clone
	@mol_id int,
	@doc_id int = null,
	@product_id int = null,
	@source_doc_id int = null,
	@draft_id int = null,
    @cloneonly bit = 1
as
begin

	set nocount on;

	if exists(select 1 from mfr_drafts where mfr_doc_id = @doc_id and product_id = @product_id and is_deleted = 0)
	begin
		raiserror('Журнал чертежей/покупных изделий текущего заказа содержит карточки. Для копирования из другого заказа необходимо предварительно очистить эти журналы.', 16, 1)
		return
	end

	BEGIN TRY
	BEGIN TRANSACTION

		declare @map as app_mapids

		if @doc_id is not null
		begin

			-- mfr_drafts
				insert into mfr_drafts(
					reserved, mfr_doc_id, product_id, d_doc, number, status_id, is_buy, work_type_1, work_type_2, work_type_3, is_root, item_id, item_price0, prop_weight, prop_size, note, add_mol_id
					)
				output inserted.reserved, inserted.draft_id into @map
				select 
					draft_id, @doc_id, @product_id, d_doc, number, status_id, is_buy, work_type_1, work_type_2, work_type_3, is_root, item_id, item_price0, prop_weight, prop_size, note, @mol_id
				from mfr_drafts
				where mfr_doc_id = @source_doc_id
					and product_id = @product_id

			-- + details
				exec mfr_draft_sync;2 @mol_id = @mol_id, @map = @map

			-- calc
				exec mfr_drafts_calc @mol_id = @mol_id, @doc_id = @doc_id, @product_id = @product_id
		end

		if @draft_id is not null
		begin

			-- copy card
				insert into mfr_drafts(
					reserved, type_id, mfr_doc_id, product_id, d_doc, number, status_id,
					is_buy, work_type_1, work_type_2, work_type_3,
					is_root, item_id, item_price0, prop_weight, prop_size, note, add_mol_id, is_deleted
					)
				output inserted.reserved, inserted.draft_id into @map
				select 
					draft_id,
					case 
                        when @cloneonly = 1 then type_id 
                        else 2 -- тех. решение (версионность тех. выписки)
                    end, 
					mfr_doc_id, product_id, d_doc,
					concat('(копия)', number),
					status_id,
					is_buy, work_type_1, work_type_2, work_type_3,
					is_root, 
                    item_id, item_price0, prop_weight, prop_size, note, @mol_id, 0
				from mfr_drafts
				where draft_id = @draft_id

			-- + details
				exec mfr_draft_sync;2 @mol_id = @mol_id, @map = @map

			-- archive old
                if @cloneonly = 0 update mfr_drafts set status_id = -1 where draft_id = @draft_id

			-- select new card
				select top 1 * from mfr_drafts where draft_id in (select new_id from @map)
		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH

end
GO
