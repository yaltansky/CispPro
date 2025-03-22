if object_id('mfr_swaps_buffer_action') is not null drop proc mfr_swaps_buffer_action
go
-- exec mfr_swaps_buffer_action 700, 'AppendInvoices'
create proc mfr_swaps_buffer_action
	@mol_id int,
	@action varchar(32),
	@queue_id uniqueidentifier = null
as
begin

  set nocount on;

	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'swp')

	BEGIN TRY
	BEGIN TRANSACTION

		if @action in ('CheckAccess')
		begin
			-- if (
			-- 	select count(distinct subject_id) 
			-- 	from mfr_swaps
			-- 	where doc_id in (select id from @buffer)
			-- 	) > 1
			-- begin
			-- 	raiserror('Замены должны быть из одного субъекта учёта.', 16, 1)
			-- end

			declare @subject_id int = (
				select top 1 subject_id
				from mfr_swaps
				where doc_id in (select id from @buffer)
				)
		
			if dbo.isinrole_byobjs(@mol_id, 
				'Admin,Mfr.Admin,Mfr.Admin.Materials',
				'SBJ', @subject_id) = 0
			begin
				raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта.', 16, 1)
			end
		end

		else if @action = 'apply'
		begin
			exec mfr_swaps_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'
			exec mfr_swaps_apply @mol_id = @mol_id, @queue_id = @queue_id
		end

		else if @action = 'check'
		begin
			exec mfr_swaps_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'
			exec mfr_swaps_check @mol_id = @mol_id, @queue_id = @queue_id
		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

end
go
