if object_id('agents_buffer_action') is not null drop proc agents_buffer_action
go
create proc agents_buffer_action
	@mol_id int,
	@action varchar(32),
	@groups varchar(max) = null
as
begin

    set nocount on;

	declare @today datetime = dbo.today()
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'a')

BEGIN TRY
BEGIN TRANSACTION

	if @action in ('CheckAccessAdmin', 'CheckAccess')
	begin
		if dbo.isinrole(@mol_id, 'Admin,Agents.Admin') = 0
		begin
			raiserror('У Вас нет доступа к модерации объектов в данном контексте.', 16, 1)
		end
	end

	else if @action = 'BindGroups' 
	begin
		exec agents_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

		insert into agents_groups(agent_id, group_id, add_mol_id)
		select i.id, g.item, @mol_id
		from @buffer i, dbo.str2rows(@groups, ',') g
	end

	else if @action = 'UnbindGroups' 
	begin
		exec agents_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

		delete x 
		from agents_groups x
			join @buffer i on i.id = x.agent_id
			join dbo.str2rows(@groups, ',') g on g.item = x.group_id
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
