if object_id('mfr_pdm_opervariant_remove') is not null drop proc mfr_pdm_opervariant_remove
go
create proc mfr_pdm_opervariant_remove
	@mol_id int,
	@pdm_id int,
	@variant_number int
as
begin

	set nocount on;

	BEGIN TRY
	BEGIN TRANSACTION

		declare @opers app_pkids
			insert into @opers select oper_id
			from mfr_pdm_opers
			where pdm_id = @pdm_id
				and variant_number = @variant_number

		delete from mfr_pdm_opers where oper_id in (select id from @opers)
		delete from mfr_pdm_opers_executors where oper_id in (select id from @opers)
		delete from mfr_pdm_opers_resources where oper_id in (select id from @opers)

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH

end
GO
