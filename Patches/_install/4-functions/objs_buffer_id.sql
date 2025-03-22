if object_id('objs_buffer_id') is not null drop function objs_buffer_id
go
create function objs_buffer_id(@mol_id int)
returns int
as
begin
	
	return (select top 1 folder_id from objs_folders where add_mol_id = @mol_id and keyword = 'buffer')

end
GO