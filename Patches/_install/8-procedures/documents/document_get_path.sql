if object_id('document_get_path') is not null drop proc document_get_path
go
create proc document_get_path
	@document_id int
as
begin

	set nocount on;

	declare @node hierarchyid = (select node from documents where document_id = @document_id);
	declare @parents table (document_id int, name varchar(250), key_owner_id int, key_owner varchar(32), is_root bit, level_id int)
		
	while @node is not null
	begin		
		if @node is not null
			insert into @parents(document_id, name, key_owner_id, key_owner, is_root, level_id)
			select 
				document_id, name, key_owner_id, key_owner, 
				case when key_owner is not null then 1 end,
				node.GetLevel()
			from documents d where node = @node
										
		if (select top 1 key_owner from documents where node = @node and is_deleted = 0) is not null
			break

		set @node = @node.GetAncestor(1)
	end

	select * from @parents order by level_id
end
GO
