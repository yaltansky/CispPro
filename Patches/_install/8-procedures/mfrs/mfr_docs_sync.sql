if object_id('mfr_docs_sync') is not null drop proc mfr_docs_sync
go
create proc mfr_docs_sync
	@mol_id int,
	@parents as app_pkids readonly
as
begin

	set nocount on;

	if (
		select count(distinct subject_id) from sdocs
		where doc_id in (select id from @parents)
		) > 1
	begin
		raiserror('Заказы должны быть из одного субъекта учёта.', 16, 1)
		return
	end

	declare @subject_id int = (
		select top 1 subject_id from sdocs
		where doc_id in (select id from @parents)
		)

	declare @proc_name varchar(50) = object_name(@@procid)
	exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @subject_id = @subject_id
    if @@error != 0 return
    
	if (
		select count(*)
		from sdocs sd
			join sdocs sd2 on sd2.doc_id = sd.parent_id
				join @parents xp on xp.id = sd2.doc_id
			join sdocs_products sp2 on sp2.doc_id = sd2.doc_id
			join sdocs_products sp on sp.doc_id = sd.doc_id and sp.product_id = sp2.product_id
	) <> (
		select count(*)
		from sdocs sd
			join sdocs sd2 on sd2.doc_id = sd.parent_id
				join @parents xp on xp.id = sd2.doc_id
	) begin
		raiserror('Готовая продукция в мастер-заказе и подчинённых заказах должна совпадать.', 16, 1)
		return
	end

BEGIN TRY
BEGIN TRANSACTION

	declare @childs as app_pkids; insert into @childs select doc_id from sdocs where parent_id in (select id from @parents)
	declare @map as app_mapids

	-- purge
		delete from sdocs_mfr_drafts where mfr_doc_id in (select id from @childs) and is_deleted = 1

	-- map olds
		declare @olds as table(mfr_doc_id int, item_id int, draft_id int, primary key(mfr_doc_id, item_id))
			insert into @olds(mfr_doc_id, item_id)
			select mfr_doc_id, item_id
			from sdocs_mfr_drafts
			where mfr_doc_id in (select id from @childs)

	-- clear
		delete from mfr_drafts where mfr_doc_id in (select id from @childs)

	-- for each parent
		declare c_parents cursor local read_only for select id as doc_id from @parents
		declare @parent_id int
		
		open c_parents; fetch next from c_parents into @parent_id
			while (@@fetch_status <> -1)
			begin
				if (@@fetch_status <> -2)
				begin

					declare c_childs cursor local read_only for select doc_id from sdocs where parent_id = @parent_id
					declare @doc_id int
		
					open c_childs; fetch next from c_childs into @doc_id
						while (@@fetch_status <> -1)
						begin
							if (@@fetch_status <> -2)
							begin
								delete @map

							-- mfr_drafts
								insert into mfr_drafts(
									reserved, mfr_doc_id, product_id, d_doc, number, status_id, is_buy, is_root, item_id, item_price0, prop_weight, prop_size, note, add_mol_id, is_deleted
									)
								output inserted.reserved, inserted.draft_id into @map
								select 
									x.draft_id, mfr.doc_id, sp.product_id, x.d_doc, x.number, x.status_id, x.is_buy, x.is_root, x.item_id, x.item_price0, x.prop_weight, x.prop_size, x.note, @mol_id, 0
								from mfr_drafts x
									join sdocs_mfr mfr on mfr.parent_id = x.mfr_doc_id
										join sdocs_products sp on sp.doc_id = mfr.doc_id
								where x.mfr_doc_id = @parent_id
									and mfr.doc_id = @doc_id
									and x.is_deleted = 0
									and (x.is_root = 0 or x.item_id = sp.product_id) -- корневой уровень - только готовая продукция

							-- + details
								exec mfr_draft_sync;2 @mol_id = @mol_id, @map = @map
							end
							--
							fetch next from c_childs into @doc_id
						end
					close c_childs; deallocate c_childs
				end
				--
				fetch next from c_parents into @parent_id
			end
		close c_parents; deallocate c_parents

	-- calc		
		exec mfr_drafts_calc @mol_id = @mol_id, @docs = @childs

	-- buffer
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'MFR', id, @mol_id
		from @childs x
		where not exists(select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'MFR' and obj_id = x.id)


COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH -- TRANSACTION

end
go
