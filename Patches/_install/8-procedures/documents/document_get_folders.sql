if object_id('document_get_folders') is not null drop procedure document_get_folders
go
create proc document_get_folders
	@mol_id int,	
	@document_id int
as
begin

	declare @parents table (document_id int, name varchar(250), key_owner_id int, key_owner varchar(32), is_root bit, level_id int)
	insert into @parents exec document_get_path @document_id = @document_id

	declare @root hierarchyid; select @root = node from documents 
	where document_id = (
		select document_id from @parents where is_root = 1	
		)

	select 
		D.DOCUMENT_ID AS NODE_ID,
		D.NAME,
		D.PARENT_ID,
		D.HAS_CHILDS,
		D.LEVEL_ID        
	from documents d
	where (d.has_childs = 1 or isnull(d.has_files,0) = 0)
		and d.node.IsDescendantOf(@root) = 1
	order by d.node

end
go