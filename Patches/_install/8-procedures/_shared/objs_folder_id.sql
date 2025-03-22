if object_id('objs_folder_id') is not null drop proc objs_folder_id
go
create proc objs_folder_id
	@mol_id int,
	@keyword varchar(100),
	@folder_id int out
as
begin
	
	set @folder_id = (select top 1 folder_id from objs_folders where add_mol_id = @mol_id and keyword = @keyword)

	if @folder_id is null
	begin
		insert into objs_folders(name, keyword, add_mol_id) values(@keyword, @keyword, @mol_id)
		select @folder_id = @@identity
	end
	else
		exec objs_folders_restore @folder_id = @folder_id
end
GO