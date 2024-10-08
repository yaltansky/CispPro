if object_id('mfr_draft_opervariant_add') is not null drop proc mfr_draft_opervariant_add
go
create proc [mfr_draft_opervariant_add]
	@mol_id int,
	@draft_id int,
	@variant_number int = null
as
begin

	set nocount on;

	BEGIN TRY
	BEGIN TRANSACTION

		update mfr_drafts_opers set variant_number = 1 where draft_id = @draft_id and variant_number is null
		declare @next_number int = (select max(variant_number) from mfr_drafts_opers where draft_id = @draft_id) + 1

	-- MFR_DRAFTS_OPERS
		declare @map_opers as table(old_oper_id int primary key, oper_id int)

		insert into mfr_drafts_opers(
			draft_id, variant_number, reserved, number, place_id, type_id, name, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, count_executors, count_resources, is_first, is_last, is_virtual, count_workers, percent_automation, operkey
			)
			output inserted.reserved, inserted.oper_id into @map_opers
		select 
			@draft_id,
			@next_number,
			x.oper_id, x.number, x.place_id, x.type_id, x.name, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.count_executors, x.count_resources, x.is_first, x.is_last, x.is_virtual, x.count_workers, x.percent_automation, x.operkey
		from mfr_drafts_opers x
		where x.draft_id = @draft_id
			and variant_number = isnull(@variant_number, 1)
			and isnull(x.is_deleted,0) = 0

	-- MFR_DRAFTS_OPERS_EXECUTORS
		insert into mfr_drafts_opers_executors(
			draft_id, oper_id, mol_id, duration_wk, duration_wk_id, note, add_mol_id, is_deleted
			)
		select 
			@draft_id, m.oper_id, x.mol_id, x.duration_wk, x.duration_wk_id, x.note, @mol_id, x.is_deleted
		from mfr_drafts_opers_executors x		
			join @map_opers m on m.old_oper_id = x.oper_id

	-- MFR_DRAFTS_OPERS_RESOURCES
		insert into mfr_drafts_opers_resources(
			draft_id, oper_id, resource_id, equipment_id, loading, note, add_mol_id, is_deleted, loading_price, loading_value
			)
		select 
			@draft_id, m.oper_id, x.resource_id, x.equipment_id, x.loading, x.note, @mol_id, x.is_deleted, x.loading_price, x.loading_value
		from mfr_drafts_opers_resources x
			join @map_opers m on m.old_oper_id = x.oper_id
		where draft_id = @draft_id

		select @next_number

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH

end
GO
