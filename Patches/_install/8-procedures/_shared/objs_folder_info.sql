if object_id('objs_folder_info') is not null drop proc objs_folder_info
go
create proc objs_folder_info
	@folder_id int
as
begin

	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	
	exec objs_folders_restore @folder_id = @folder_id

	declare @node hierarchyid = (select node from objs_folders where folder_id = @folder_id)

	declare @update_date datetime = (
		select max(update_date)
		from objs_folders
		where node.IsDescendantOf(@node) = 1
			and has_childs = 0
			and is_deleted = 0
			and update_date is not null
		)

	declare @update_mol_name varchar(50)
	if @update_date is not null
		set @update_mol_name = (
			select max(m.name)
			from objs_folders f
				join mols m on m.mol_id = f.update_mol_id
			where node.IsDescendantOf(@node) = 1
				and f.has_childs = 0
				and f.is_deleted = 0
				and f.update_date = @update_date
			)

	declare @path varchar(max); exec objs_folder_path @folder_id = @folder_id, @path = @path out

	select
		F.FOLDER_ID,
		NAME = @path,
		ADD_DATE,
		ADD_MOL_NAME = (select name from mols where mol_id = f.add_mol_id),
		UPDATE_DATE = @update_date,
		UPDATE_MOL_NAME = @update_mol_name,
		COUNT_FOLDERS = (
			select count(*)
			from objs_folders
			where keyword = f.keyword				
				and node.IsDescendantOf(f.node) = 1
				and folder_id <> f.folder_id
				and has_childs = 1
			),
		COUNT_ITEMS = (
			select count(*)
			from objs_folders
			where keyword = f.keyword				
				and node.IsDescendantOf(f.node) = 1
				and folder_id <> f.folder_id
				and has_childs = 0
			),
		COUNT_OBJECTS = (
			select sum(xf.counts)
			from objs_folders xf
			where xf.keyword = f.keyword				
				and node.IsDescendantOf(f.node) = 1
				and xf.folder_id <> f.folder_id
				and xf.has_childs = 0
			)
	from objs_folders f
	where folder_id = @folder_id

end
GO
