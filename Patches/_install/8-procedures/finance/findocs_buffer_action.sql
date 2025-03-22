if object_id('findocs_buffer_action') is not null drop proc findocs_buffer_action
go
create proc findocs_buffer_action
	@mol_id int,
	@action varchar(32)
as
begin

    set nocount on;

	declare @today datetime = dbo.today()
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	
	create table #buffer(id int primary key)
	insert into #buffer select id from dbo.objs_buffer(@mol_id, 'fd')

	BEGIN TRY
	BEGIN TRANSACTION

		if @action = 'CheckDealsAgents' 
		begin

			declare @check app_pkids		
				insert into @check select distinct fd.findoc_id
				from findocs# fd
					join #buffer i on i.id = fd.findoc_id
					join agents a on a.agent_id = fd.agent_id
					join deals d on d.budget_id = fd.budget_id
						join agents a2 on a2.agent_id = d.customer_id
				where (
					isnull(a.inn, '') != isnull(a2.inn, '')
					or fd.agent_id != d.customer_id
					)

			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'fd'
			
			if exists(select 1 from @check)
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'fd', id, 0 from @check
		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

	exec drop_temp_table '#buffer'
end
go
