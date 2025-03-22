if object_id('document_move') is not null drop procedure document_move
go
create procedure document_move
	@document_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	if @where = 'into' set @where = 'first'
	if @where = 'into_last' set @where = 'into'

	declare @root_id int

	if @target_id is null
	begin
		declare @owner_id int, @owner_key varchar(32); exec document_get_owner @document_id, @owner_id out, @owner_key out
		set @root_id = (select top 1 document_id from documents where key_owner = @owner_key and is_deleted = 0)
		set @target_id = @root_id
	end

	exec tree_move_node 
		@table_name = 'documents',
		@key_name = 'document_id',
		@source_id = @document_id,
		@target_id = @target_id,
		@where = @where

	if @root_id is not null exec documents_calc @root_id = @root_id
end
go
