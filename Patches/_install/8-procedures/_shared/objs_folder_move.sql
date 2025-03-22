if object_id('objs_folder_move') is not null drop procedure objs_folder_move
go
create procedure objs_folder_move
	@folder_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	if @where = 'into' set @where = 'first'

	declare @keyword varchar(30) = (select keyword from objs_folders where folder_id = @folder_id)
	declare @where_rows varchar(100) = 'keyword = ''' + @keyword + ''''

	exec tree_move_node 
		@table_name = 'objs_folders',
		@key_name = 'folder_id',
		@where_rows = @where_rows,
		@source_id = @folder_id,
		@target_id = @target_id,
		@where = @where

end
go
