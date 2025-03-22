if object_id('objs_folder_contains') is not null drop proc objs_folder_contains
go
create proc objs_folder_contains
	@folder_id int,
	@obj_type varchar(10),
	@ids varchar(max)
as
begin

	declare @idds app_pkids
	insert into @idds 
	select distinct item from dbo.str2rows(@ids, ',')
	where try_cast(item as int) is not null

	select fd.obj_id
	from objs_folders_details fd with(nolock)
		join @idds i on i.id = fd.obj_id
	where fd.folder_id = @folder_id
		and fd.obj_type = @obj_type

end
GO
