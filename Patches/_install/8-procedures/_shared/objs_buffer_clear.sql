if object_id('objs_buffer_clear') is not null drop proc objs_buffer_clear
go
create proc objs_buffer_clear
	@mol_id int,
	@obj_type varchar(16) = null
as
begin
	delete from objs_folders_details where folder_id = dbo.objs_buffer_id(@mol_id)
		and obj_type = isnull(@obj_type,obj_type)
end
go
