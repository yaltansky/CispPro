if object_id('mfr_draft_opervariant_remove') is not null drop proc mfr_draft_opervariant_remove
go
create proc [mfr_draft_opervariant_remove]
	@mol_id int,
	@draft_id int,
	@variant_number int
as
begin

	set nocount on;

	BEGIN TRY
	BEGIN TRANSACTION

		declare @opers app_pkids
		insert into @opers select oper_id
		from mfr_drafts_opers
		where draft_id = @draft_id
			and variant_number = @variant_number

		delete from mfr_drafts_opers where oper_id in (select id from @opers)
		delete from mfr_drafts_opers_executors where oper_id in (select id from @opers)
		delete from mfr_drafts_opers_resources where oper_id in (select id from @opers)

		declare @min int = (select min(variant_number) from mfr_drafts_opers where draft_id = @draft_id)
		if @min > 1 update mfr_drafts_opers set variant_number = 1 where draft_id = @draft_id and variant_number = @min

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH

end
GO
