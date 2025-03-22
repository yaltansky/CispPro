if object_id('objs_folders_calc') is not null drop proc objs_folders_calc
go
create proc objs_folders_calc
	@mol_id int,
	@keyword varchar(32)
as
begin
	
	declare @where_rows varchar(100) = 'keyword = ''' + @keyword + ''''
	exec tree_calc_nodes 'objs_folders', 'folder_id', @where_rows = @where_rows, @sortable = 0

end
GO