if object_id('objs_folder_action') is not null drop proc objs_folder_action
go
create proc objs_folder_action
	@mol_id int,	
	@action_name varchar(30), -- 'placeToBuffer'
	@folder_id int
as
begin
	
	set nocount on;

	exec objs_folders_restore @folder_id = @folder_id
	
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin')
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @obj_type varchar(16)
	
	select @obj_type = obj_type	from objs_folders where folder_id = @folder_id

	if @action_name = 'placeToBuffer'
	begin
		exec sys_set_triggers 0
			delete from objs_folders_details where folder_id = @buffer_id

			create table #ids(id int primary key)
				exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'

				insert into objs_folders_details(folder_id, obj_id, obj_type, add_mol_id)
				select @buffer_id, id, @obj_type, @mol_id from #ids		
			exec drop_temp_table '#ids'
		exec sys_set_triggers 1
	end

	if @action_name = 'addFolderNews'
	begin
        declare @folder hierarchyid, @keyword varchar(30)
            select @folder = node, @keyword = keyword from objs_folders where folder_id = @folder_id
    
        create table #folders(folder_id int primary key)
            insert into #folders(folder_id)
            select folder_id
            from objs_folders
            where keyword = @keyword
                and node.IsDescendantOf(@folder) = 1
                and is_deleted = 0
    
        exec objs_buffer_clear @mol_id = @mol_id, @obj_type = @obj_type

        if @obj_type = 'SD'
        begin
            -- TODO: убрать зависимость от типа документа (SDOCS.TYPE_ID) <-- надо радлелить типы объекта по представлениям (view)
            declare @sdoc_type_id int = (
                select top 1 type_id from sdocs where doc_id in (
                    select top 1 obj_id from objs_folders_details where folder_id in (select folder_id from #folders)
                        and obj_type = 'sd'
                    )
                )
            
            insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
            select @buffer_id, @obj_type, doc_id, @mol_id
            from sdocs x
            where (@sdoc_type_id is null or type_id = @sdoc_type_id)
                and status_id != -1 -- exclude deleted
                and not exists(
                    select 1 from objs_folders_details fd
                        join #folders i on i.folder_id = fd.folder_id
                    where obj_type = @obj_type
                        and obj_id = x.doc_id
                    )
        end

        else begin

            declare @base_table varchar(100), @base_column varchar(100)
            select @base_table = base_table, @base_column = base_table_column from objs_types where type = @obj_type 

            if @base_table is null or @base_column is null
                raiserror('Получение новостей в данном контексте не предусмотрено.', 16, 1)
            else begin

                declare @sql nvarchar(max) = N'
                    insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                    select top 100000 @buffer_id, @obj_type, <base_column>, @mol_id
                    from <base_table> x
                    where status_id >= 0
                        and not exists(
                            select 1 from objs_folders_details fd
                                join #folders i on i.folder_id = fd.folder_id
                            where obj_type = @obj_type
                                and obj_id = x.<base_column>
                        )
                '

                set @sql = replace(@sql, '<base_table>', @base_table)
                set @sql = replace(@sql, '<base_column>', @base_column)
                exec sp_executesql @sql, N'
                    @mol_id int,
                    @buffer_id int,
                    @obj_type varchar(16)
                    ',
                    @mol_id, @buffer_id, @obj_type
            end
        end
        exec drop_temp_table '#folders'
    end
end
GO
