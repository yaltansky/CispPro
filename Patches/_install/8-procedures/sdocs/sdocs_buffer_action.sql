if object_id('sdocs_buffer_action') is not null drop proc sdocs_buffer_action
go
create proc sdocs_buffer_action
	@mol_id int,
	@action varchar(32),
	@status_id int = null,
	@status_mol_id int = null
as
begin

    set nocount on;

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'SD')

	if (
		select count(distinct subject_id) from sdocs
			join @buffer i on i.id = sdocs.doc_id
		) > 1
	begin
		raiserror('В буфере должны быть товарные документы одного субъекта учёта.', 16, 1)
		return
	end

	declare @subject_id int = (
		select top 1 subject_id from sdocs
		join @buffer i on i.id = sdocs.doc_id
		)

BEGIN TRY
BEGIN TRANSACTION

	if @action = 'bindStatus'
	begin
		if dbo.isinrole_byobjs(@mol_id, 
			'Mfr.Admin.Materials,Mfr.Moderator.Materials',
			'SBJ', @subject_id) = 0
		begin
			raiserror('У Вас нет доступа для выполнения действия над объектами в данном субъекте учёта.', 16, 1)
		end

		if (
			select count(distinct type_id) from sdocs
				join @buffer i on i.id = sdocs.doc_id
			) > 1
		begin
			raiserror('В буфере должны быть товарные документы одного типа.', 16, 1)
		end

		declare @type_id int = (
			select top 1 type_id from sdocs
			join @buffer i on i.id = sdocs.doc_id
			)

		update x set 
			status_id = @status_id,
			update_mol_id = @mol_id, update_date = getdate()
		from sdocs x
			join @buffer i on i.id = x.doc_id

		if @status_id = 2 -- Отправлено
			update x set executor_id = @status_mol_id
			from sdocs x
				join @buffer i on i.id = x.doc_id
		else if @status_id = 10 -- Исполнение
			update x set mol_to_id = @status_mol_id
			from sdocs x
				join @buffer i on i.id = x.doc_id
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
