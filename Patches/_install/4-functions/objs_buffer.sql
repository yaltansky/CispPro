if object_id('objs_buffer') is not null drop function objs_buffer
go
create function objs_buffer(@mol_id int, @obj_type varchar(16))
returns @ids table(id int primary key)
as
begin
	
	insert into @ids
	select obj_id from objs_folders_details where folder_id = dbo.objs_buffer_id(@mol_id)
		and obj_type = isnull(@obj_type, obj_type)

	return;
end
go
