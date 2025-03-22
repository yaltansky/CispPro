if object_id('mfr_opers_action') is not null drop proc mfr_opers_action
go
-- exec mfr_opers_action 700, 449680, @action = 'ShowOthers'
create proc mfr_opers_action
	@mol_id int,
	@doc_id int,
	@product_id int = null,
	@action varchar(32)
as
begin

    set nocount on;

	if @product_id is null select top 1 @product_id = product_id from sdocs_products where doc_id = @doc_id

	if @action = 'Sync' exec mfr_opers_action;2 @mol_id = @mol_id, @doc_id = @doc_id, @product_id = @product_id
	else if @action = 'Push' exec mfr_opers_action;3 @mol_id = @mol_id, @doc_id = @doc_id, @product_id = @product_id
	else if @action = 'Pull' exec mfr_opers_action;4 @mol_id = @mol_id, @doc_id = @doc_id, @product_id = @product_id
	else if @action = 'Unbind' exec mfr_opers_action;5 @mol_id = @mol_id, @doc_id = @doc_id, @product_id = @product_id
	else if @action = 'ShowOthers' exec mfr_opers_action;6 @mol_id = @mol_id, @doc_id = @doc_id, @product_id = @product_id
end
go
-- sync
create proc mfr_opers_action;2 @mol_id int,	 @doc_id int, @product_id int = null
as
begin

	set nocount on;

	declare @keyword varchar(50), @project_id int
	exec mfr_opers_action;10 @doc_id = @doc_id, @product_id = @product_id, @keyword = @keyword out, @project_id = @project_id out

	declare @folders table(
		row_id int identity primary key, 
		folder_id int index ix_folder_id, 
		name varchar(50), parent_id int, task_id int, parent_task_id int,
		is_new bit default 0
		)

	declare @numpad int = len(cast((select count(*) from projects_tasks where project_id = @project_id and is_deleted = 0) as varchar))
	if @numpad is null or @numpad > 4 set @numpad = 4

	insert into @folders(task_id, parent_task_id, name)
	select task_id, parent_id, 
		substring(
			concat(right('0000' + cast(task_number as varchar), @numpad), '.', name)
		, 1, 50)
	from projects_tasks
	where project_id = @project_id
		and is_deleted = 0
	order by node

	update x
	set folder_id = f.folder_id
	from @folders x
		join objs_folders f on f.keyword = @keyword and f.extern_id = x.task_id

BEGIN TRY
BEGIN TRANSACTION

	declare @folders_seed int = isnull((select max(folder_id) from objs_folders), 0)

	update x
	set folder_id = @folders_seed + new_row_id, is_new = 1
	from @folders x
		join (
			select row_id,
				row_number() over (order by row_id) as new_row_id
			from @folders
			where folder_id is null
		) xx on xx.row_id = x.row_id

	update x
	set parent_id = xx.folder_id
	from @folders x
		join @folders xx on xx.task_id = x.parent_task_id

	SET IDENTITY_INSERT OBJS_FOLDERS ON
		insert into objs_folders(keyword, obj_type, folder_id, parent_id, name, add_mol_id, extern_id)
		select @keyword, 'MFO', folder_id, parent_id, name, @mol_id, task_id
		from @folders
		where is_new = 1
				
		if @@rowcount >= 1 exec objs_folders_calc @mol_id = @mol_id, @keyword = @keyword
	SET IDENTITY_INSERT OBJS_FOLDERS OFF

	update x
	set name = f.name,
		parent_id = f.parent_id
	from objs_folders x
		join @folders f on f.folder_id = x.folder_id
	where x.keyword = @keyword
		and f.is_new = 0

	update objs_folders set is_deleted = 1
	where keyword = @keyword
		and not exists(select 1 from @folders where task_id = objs_folders.extern_id)

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH

end
GO
-- push
create proc mfr_opers_action;3  @mol_id int,	 @doc_id int, @product_id int as return
GO
-- pull
create proc mfr_opers_action;4  @mol_id int,	 @doc_id int, @product_id int as return
GO
-- unbind
create proc mfr_opers_action;5  @mol_id int,	 @doc_id int, @product_id int as return
GO
-- showOthers
create proc mfr_opers_action;6  @mol_id int,	 @doc_id int, @product_id int as
begin

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')

	declare @keyword varchar(50), @project_id int
	exec mfr_opers_action;10 @doc_id = @doc_id, @product_id = @product_id, @keyword = @keyword out, @project_id = @project_id out

	declare @opers table(oper_id int primary key)
	insert into @opers select oper_id from sdocs_mfr_opers where mfr_doc_id = @doc_id and product_id = @product_id

	delete x from @opers x
		join objs_folders_details fd on fd.obj_type = 'mfo' and fd.obj_id = x.oper_id
			join objs_folders f on f.folder_id = fd.folder_id and f.keyword = @keyword and f.is_deleted = 0

	delete from objs_folders_details where folder_id = @buffer_id

	insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
	select @buffer_id, 'mfo', oper_id, @mol_id from @opers
end
GO
-- helper: keyword
create proc mfr_opers_action;10  @doc_id int, @product_id int,
	@keyword varchar(50) out,
	@project_id int out
as
begin
	set @keyword = concat('mfo-', @doc_id)
	set @project_id = (select top 1 project_id from projects where REFKEY = concat('/mfrs/docs/', @doc_id, '/opers'))
end
GO
