if object_id('document_get_owner') is not null drop proc document_get_owner
go
create proc document_get_owner
	@document_id int,
	@owner_id int out,
	@owner_key varchar(32) out
as
begin

	declare @parents table (document_id int, name varchar(250), key_owner_id int, key_owner varchar(32), is_root bit, level_id int)
	insert into @parents exec document_get_path @document_id = @document_id

	select @owner_id = key_owner_id, @owner_key = key_owner from @parents where is_root = 1

    if @owner_id is null
	    select @owner_id = key_owner_id, @owner_key = key_owner from documents where document_id = @document_id
end
GO
