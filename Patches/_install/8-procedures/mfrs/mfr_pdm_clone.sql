if object_id('mfr_pdm_clone') is not null drop proc mfr_pdm_clone
go
create proc mfr_pdm_clone
	@mol_id int,
	@pdm_id int,
    @cloneVersion bit = 0
as
begin
	set nocount on;

	BEGIN TRY
	BEGIN TRANSACTION

		declare @item_id int = (select item_id from mfr_pdms where pdm_id = @pdm_id)
		declare @next_number varchar(30) = 
            (select 1 + count(*) from mfr_pdms where item_id = @item_id and is_deleted = 0)

        if @cloneVersion = 0 set @next_number = '1';

	-- MFR_PDMS
		declare @new_id int, @news app_pkids
		insert into mfr_pdms(version_number, number, item_id, d_doc, status_id, add_mol_id)
			output inserted.pdm_id into @news
		select @next_number, 
            case when @cloneVersion = 1 then '' else '(копия) ' end + number,
            case when @cloneVersion = 1 then item_id end,
            dbo.today(), 0, @mol_id
		from mfr_pdms
		where pdm_id = @pdm_id

		select @new_id = id from @news

	-- MFR_PDM_OPTIONS
		declare @map_options as table(old_id int primary key, id int)

		insert into mfr_pdm_options(
			reserved, pdm_id,
			group_name, name, note, add_mol_id
			)
			output inserted.reserved, inserted.pdm_option_id into @map_options
		select 
			x.pdm_option_id, x.pdm_id,
			group_name, name, note, @mol_id
		from mfr_pdm_options x with(nolock)
		where x.pdm_id = @pdm_id
			and isnull(x.is_deleted,0) = 0
 
 	-- MFR_PDM_ITEMS
		declare @map_items as table(old_id int primary key, id int)

		insert into mfr_pdm_items(
			reserved, pdm_id,
			place_id, item_type_id, parent_id, pdm_option_id, item_id, numpos, unit_name, q_netto, q_brutto, is_buy
			)
			output inserted.reserved, inserted.id into @map_items
		select 
			x.id, @new_id,
			place_id, item_type_id, parent_id, pdm_option_id, item_id, numpos, unit_name, q_netto, q_brutto, is_buy
		from mfr_pdm_items x with(nolock)
		where x.pdm_id = @pdm_id
			and isnull(x.is_deleted,0) = 0
        order by x.id

		update x set parent_id = map.id
		from mfr_pdm_items x
			join @map_items i on i.id = x.id
			join @map_items map on map.old_id = x.parent_id

		update x set pdm_option_id = map.id
		from mfr_pdm_items x with(nolock)
			join @map_items i on i.id = x.id
			join @map_options map on map.old_id = x.pdm_option_id

	-- MFR_PDM_OPERS
		declare @map_opers as table(old_id int primary key, id int)

		insert into mfr_pdm_opers(
			reserved, pdm_id, variant_number,
			number, place_id, type_id, name, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, count_executors, count_resources, is_first, is_last, count_workers, operkey
			)
			output inserted.reserved, inserted.oper_id into @map_opers
		select 
			x.oper_id, @new_id, x.variant_number,
			x.number, x.place_id, x.type_id, x.name, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.count_executors, x.count_resources, x.is_first, x.is_last, x.count_workers, x.operkey
		from mfr_pdm_opers x with(nolock)
		where x.pdm_id = @pdm_id
			and isnull(x.is_deleted,0) = 0

	-- MFR_PDM_OPERS_EXECUTORS
		insert into mfr_pdm_opers_executors(
			pdm_id, oper_id, post_id, duration_wk, duration_wk_id, note, add_mol_id
			)
		select 
			@new_id, m.id, x.post_id, x.duration_wk, x.duration_wk_id, x.note, @mol_id
		from mfr_pdm_opers_executors x with(nolock)
			join @map_opers m on m.old_id = x.oper_id
		where isnull(x.is_deleted,0) = 0

	-- MFR_PDM_OPERS_RESOURCES
		insert into mfr_pdm_opers_resources(
			pdm_id, oper_id, resource_id, loading, note, add_mol_id, is_deleted, loading_price, loading_value
			)
		select 
			@new_id, m.id, x.resource_id, x.loading, x.note, @mol_id, x.is_deleted, x.loading_price, x.loading_value
		from mfr_pdm_opers_resources x with(nolock)
			join @map_opers m on m.old_id = x.oper_id
		where pdm_id = @pdm_id

	-- return
		SELECT * FROM MFR_PDMS WHERE PDM_ID = @NEW_ID

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH

end
GO
