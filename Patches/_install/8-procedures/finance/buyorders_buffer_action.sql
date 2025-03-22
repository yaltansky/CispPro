if object_id('buyorders_buffer_action') is not null drop proc buyorders_buffer_action
go
create proc buyorders_buffer_action
	@mol_id int,
	@action varchar(32)
as
begin

    set nocount on;

	declare @today datetime = dbo.today()
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'sd')

BEGIN TRY
BEGIN TRANSACTION

	if @action = 'CheckAccess'
	begin
		if (
			select count(distinct sd.subject_id) 
			from sdocs sd
			where doc_id in (select id from @buffer)
			) > 1
		begin
			raiserror('Заявки на закупку должны быть из одного субъекта учёта.', 16, 1)
		end

		declare @subject_id int = (
			select top 1 sd.subject_id
			from sdocs sd
			where doc_id in (select id from @buffer)
			)
	
		if dbo.isinrole_byobjs(@mol_id, 
			'Mfr.Admin.Materials',
			'SBJ', @subject_id) = 0
		begin
			raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта (роль Mfr.Admin.Materials).', 16, 1)
		end
	end

	else if @action = 'SendExecuting' 
	begin
		exec buyorders_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

		update x set status_id = 10 -- Исполнение
		from sdocs x
			join @buffer i on i.id = x.doc_id
		where x.status_id = 0

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
