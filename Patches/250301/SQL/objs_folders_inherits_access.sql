if object_id('objs_folders_inherits_access') is not null drop proc objs_folders_inherits_access
go
create proc objs_folders_inherits_access
	@folder_id int,
    @keyword varchar(32)
as
begin
    declare @node hierarchyid = (select node from objs_folders where folder_id = @folder_id);
    update objs_folders set inherited_access = 1 where keyword = @keyword and node.IsDescendantOf(@node) = 1;
    exec objs_folders_calc_access @folder_id = @folder_id;
end
go
