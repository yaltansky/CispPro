if object_id('objs_folder_toggle') is not null drop procedure objs_folder_toggle
go
create procedure objs_folder_toggle
	@mol_id int,
	@folder_id int,
	@is_deleted bit = null
AS  
begin  

	declare @keyword varchar(30), @folder hierarchyid
	
	select 
		@keyword = keyword,
		@folder = node,
		@is_deleted = 
			case
				when @is_deleted is null then 
					case when isnull(is_deleted,0) = 1 then 0 else 1 end
				else @is_deleted
			end
	from objs_folders where folder_id = @folder_id

	if @folder is not null
		update objs_folders
		set is_deleted = @is_deleted,
			update_date = getdate(),
			update_mol_id = @mol_id
		where keyword = @keyword
			and (
				node.IsDescendantOf(@folder) = 1
				or (@is_deleted = 0 and @folder.IsDescendantOf(node) = 1)
				)

	else begin

		declare @rows table(parent_id int, folder_id int index ix_folder)

		-- childs of @folder_id
		;with tree as (
			select parent_id, folder_id from objs_folders where folder_id = @folder_id
			union all
			select x.parent_id, x.folder_id
			from objs_folders x
				join tree on tree.folder_id = x.parent_id
			)
			insert into @rows(parent_id, folder_id)
			select parent_id, folder_id from tree

		-- parents of @folder_id
		;with tree as (
			select parent_id, folder_id from objs_folders where folder_id = @folder_id
			union all
			select x.parent_id, x.folder_id
			from objs_folders x
				join tree on tree.parent_id = x.folder_id
			)
			insert into @rows(parent_id, folder_id)
			select parent_id, folder_id from tree

		update x
		set is_deleted = @is_deleted,
			update_date = getdate(),
			update_mol_id = @mol_id
		from objs_folders x
			join @rows r on r.folder_id = x.folder_id

		exec objs_folders_calc -25, @keyword = @keyword
	end

end
go
