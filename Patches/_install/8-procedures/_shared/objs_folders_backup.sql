if object_id('objs_folders_backup') is not null drop procedure objs_folders_backup
go
/***
declare @folders as app_pkids; 
	insert into @folders select folder_id from objs_folders 
	where datediff(d, read_date, getdate()) > 30 
		and keyword != 'buffer'
		and folder_id not in (select folder_id from zip_objs_folders)
exec objs_folders_backup @ids = @folders
***/
create procedure objs_folders_backup
	@folder_id int = null,
	@ids app_pkids readonly
AS  
begin  

	set nocount on;

	create table #folders(id int primary key)

	if @folder_id is not null
		insert into #folders select @folder_id
	else
		insert into #folders select id from @ids

	exec objs_folders_backup;2

	if not exists(
		select 1 from zip_objs_folders
		where folder_id in (select id from #folders)
		)
	begin

		BEGIN TRY
		BEGIN TRANSACTION
			
			EXEC SYS_SET_TRIGGERS 0

				insert into zip_objs_folders(folder_id, keyword, name, obj_type)
				select folder_id, keyword, name, obj_type
				from objs_folders f
					join #folders fx on fx.id = f.folder_id

				insert into zip_objs_folders_details(folder_id, obj_type, obj_id, add_mol_id, add_date)
				select folder_id, obj_type, obj_id, add_mol_id, add_date
				from objs_folders_details fd
					join #folders fx on fx.id = fd.folder_id
				where fd.obj_type is not null
		
				delete x from objs_folders_details x
					join #folders i on i.id = x.folder_id

			EXEC SYS_SET_TRIGGERS 1

		COMMIT TRANSACTION
		END TRY

		BEGIN CATCH
			declare @err varchar(max) = error_message()
			IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION	
			exec sys_set_triggers 1
			raiserror (@err, 16, 1)
		END CATCH
	end

	else 
		raiserror('Указанные папки уже архивированы. Необходимо уточнить выборку.', 16, 1)
end
go
-- helper: create tables
create procedure objs_folders_backup;2
as
begin


	IF OBJECT_ID('ZIP_OBJS_FOLDERS') IS NULL
		EXEC SP_EXECUTESQL N'
		CREATE TABLE ZIP_OBJS_FOLDERS(
			FOLDER_ID INT PRIMARY KEY,
			KEYWORD VARCHAR(32),
			NAME VARCHAR(128),
			OBJ_TYPE VARCHAR(16)
		)
		'

	IF OBJECT_ID('ZIP_OBJS_FOLDERS_DETAILS') IS NULL
		EXEC SP_EXECUTESQL N'
		CREATE TABLE ZIP_OBJS_FOLDERS_DETAILS(
			FOLDER_ID INT,
			OBJ_TYPE VARCHAR(16),
			OBJ_ID INT,
			ADD_DATE DATETIME,
			ADD_MOL_ID INT,
			PRIMARY KEY (FOLDER_ID, OBJ_TYPE, OBJ_ID)
		)
		'
end
go
