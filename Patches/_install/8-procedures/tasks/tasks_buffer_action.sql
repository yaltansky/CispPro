if object_id('tasks_buffer_action') is not null drop proc tasks_buffer_action
go
-- exec tasks_buffer_action 700, 'bindPersons', 800, null
create proc tasks_buffer_action
	@mol_id int,
	@action varchar(32),
	@author_id int = null,
	@analyzer_id int = null,
	@reader_id int = null,
	@exclude_reader_id int = null
as
begin

    set nocount on;

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'TSK')

BEGIN TRY
BEGIN TRANSACTION

	if @action in ('CheckAccessAdmin', 'CheckAccess')
	begin
		if dbo.isinrole(@mol_id, 'Admin'	) = 0
		begin
			raiserror('У Вас нет доступа к модерации объектов в данном контексте.', 16, 1)
		end
	end

	else if @action = 'bindPersons'
	begin
		exec tasks_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

		if @author_id is not null
			insert into tasks_hists(task_id, action_name, description, mol_id)
			select 
				id, 'Смена автора', concat('Изменён автор задачи с ', m.name, ' на ', m2.name, '.'),
				@mol_id
			from tasks x
				join @buffer buf on buf.id = x.task_id
				join mols m on m.mol_id = x.author_id
				join mols m2 on m2.mol_id = @author_id

		if @analyzer_id is not null
			insert into tasks_hists(task_id, action_name, description, mol_id)
			select 
				id, 'Смена координатора', concat('Изменён координатор задачи с ', m.name, ' на ', m2.name, '.'),
				@mol_id
			from tasks x
				join @buffer buf on buf.id = x.task_id
				join mols m on m.mol_id = x.analyzer_id
				join mols m2 on m2.mol_id = @analyzer_id

		if @reader_id is not null
		begin
			insert into tasks_mols(task_id, role_id, mol_id, add_date)
			select 
				x.task_id,
				2, -- reader
				@reader_id,
				getdate()
			from tasks x
				join @buffer buf on buf.id = x.task_id
			where not exists(select 1 from tasks_mols where task_id = x.task_id and mol_id = @reader_id)

			if @@rowcount > 0
				insert into tasks_hists(task_id, action_name, description, mol_id)
				select 
					id, 
					'Добавлен участник',
					concat('Добавлен участник: ', mols.name),
					@mol_id
				from tasks x
					join @buffer buf on buf.id = x.task_id
					join mols on mols.mol_id = @reader_id
		end

		if @exclude_reader_id is not null
		begin
			delete x from tasks_mols x
				join @buffer buf on buf.id = x.task_id
			where x.mol_id = @exclude_reader_id
		end

		if @author_id is not null or @analyzer_id is not null
			update x set 
				author_id = isnull(@author_id, x.author_id),
				analyzer_id = isnull(@analyzer_id, x.analyzer_id)
			from tasks x
				join @buffer buf on buf.id = x.task_id
	end

	else if @action = 'Close'
	begin
		exec tasks_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

		insert into tasks_hists(task_id, action_id, action_name, description, mol_id)
		select id, 'Close', 'Закрыть', 'Задача была закрыта администратором.', @mol_id
		from tasks x
			join @buffer buf on buf.id = x.task_id

		update x set status_id = 5
		from tasks x
			join @buffer buf on buf.id = x.task_id
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
