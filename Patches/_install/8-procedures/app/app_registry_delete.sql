if object_id('app_registry_delete') is not null drop proc app_registry_delete
go
create proc app_registry_delete
	@source_id int
as
begin
    set nocount on;

	declare @parent_node hierarchyid = (select node from app_registry where id = @source_id)
	if @parent_node is null return

	update app_registry set 
		parent_id = null,
		is_deleted = case when registry_id is null then 1 else 0 end
	where node.IsDescendantOf(@parent_node) = 1

	exec tree_calc_nodes 'app_registry', 'id'
end
go
