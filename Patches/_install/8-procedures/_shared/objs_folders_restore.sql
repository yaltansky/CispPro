if object_id('objs_folders_restore') is not null drop procedure objs_folders_restore
go
create procedure objs_folders_restore
	@folder_id int = null,
	@ids app_pkids readonly
AS  
begin  

	set nocount on;

	if db_name() not in ('CISP') 
		return -- only for main database

	declare @folders as app_pkids

	if @folder_id is not null
		insert into @folders select @folder_id
	else
		insert into @folders select id from @ids

	if exists(select 1 from sys.tables where name = 'zip_objs_folders')
	begin
		if exists(
			select 1 from zip_objs_folders
			where folder_id in (select id from @folders)
			)
		begin

			BEGIN TRY
			BEGIN TRANSACTION
				
				exec sys_set_triggers 0
					insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id, add_date)
					select folder_id, obj_type, obj_id, add_mol_id, add_date
					from zip_objs_folders_details fd
						join @folders fx on fx.id = fd.folder_id
		
					delete from zip_objs_folders where folder_id in (select id from @folders)
					delete from zip_objs_folders_details where folder_id in (select id from @folders)
				exec sys_set_triggers 1

			COMMIT TRANSACTION
			END TRY

			BEGIN CATCH
				declare @err varchar(max) = error_message()
				IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION	
				exec sys_set_triggers 1
				raiserror (@err, 16, 1)
			END CATCH
		end
	end
end
go
