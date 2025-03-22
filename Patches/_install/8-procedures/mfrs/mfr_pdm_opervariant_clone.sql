if object_id('mfr_pdm_opervariant_clone') is not null drop proc mfr_pdm_opervariant_clone
go
create proc mfr_pdm_opervariant_clone
	@mol_id int,
	@pdm_id int,
	@variant_number int = null
as
begin

	set nocount on;

	BEGIN TRY
	BEGIN TRANSACTION

		declare @next_number int = (select max(variant_number) from mfr_pdm_opers where pdm_id = @pdm_id) + 1

	-- MFR_PDM_OPERS
		declare @map_opers as table(old_oper_id int primary key, oper_id int)

		insert into mfr_pdm_opers(
			pdm_id, variant_number, reserved, number, place_id, type_id, name, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, count_executors, count_resources, is_first, is_last, count_workers, operkey
			)
			output inserted.reserved, inserted.oper_id into @map_opers
		select 
			@pdm_id,
			@next_number,
			x.oper_id, x.number, x.place_id, x.type_id, x.name, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.count_executors, x.count_resources, x.is_first, x.is_last, x.count_workers, x.operkey
		from mfr_pdm_opers x
		where x.pdm_id = @pdm_id
			and variant_number = isnull(@variant_number, 1)
			and isnull(x.is_deleted,0) = 0

	-- MFR_PDM_OPERS_EXECUTORS
		insert into mfr_pdm_opers_executors(
			pdm_id, oper_id, post_id, duration_wk, duration_wk_id, note, add_mol_id, is_deleted
			)
		select 
			@pdm_id, m.oper_id, x.post_id, x.duration_wk, x.duration_wk_id, x.note, @mol_id, x.is_deleted
		from mfr_pdm_opers_executors x		
			join @map_opers m on m.old_oper_id = x.oper_id

	-- MFR_PDM_OPERS_RESOURCES
		insert into mfr_pdm_opers_resources(
			pdm_id, oper_id, resource_id, loading, note, add_mol_id, is_deleted, loading_price, loading_value
			)
		select 
			@pdm_id, m.oper_id, x.resource_id, x.loading, x.note, @mol_id, x.is_deleted, x.loading_price, x.loading_value
		from mfr_pdm_opers_resources x
			join @map_opers m on m.old_oper_id = x.oper_id
		where pdm_id = @pdm_id

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
