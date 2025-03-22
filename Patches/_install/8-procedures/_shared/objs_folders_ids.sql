if object_id('objs_folders_ids') is not null drop proc objs_folders_ids
go
create proc objs_folders_ids
	@folder_id int,
	@obj_type varchar(16) = null,
	@temp_table sysname = null
as
begin

	set nocount on;

	declare @node hierarchyid, @keyword varchar(32)
		select @node = node, @keyword = keyword from objs_folders
		where folder_id = @folder_id and keyword <> 'BUFFER'

	set @keyword = isnull(@keyword, 'BUFFER')
	
	-- folders
	declare @folders as app_pkids
		insert into @folders
		select folder_id
		from objs_folders with(nolock)
		where folder_id = @folder_id
			or folder_id in (
				select folder_id from objs_folders with(nolock)
				where keyword = @keyword
					and node.IsDescendantOf(@node) = 1
					and is_deleted = 0
				)
	
	exec objs_folders_restore @ids = @folders

	-- read statistics
	update x set read_date = getdate(), read_count = isnull(read_count,0) + 1
	from objs_folders x
		join @folders i on i.id = x.folder_id

	-- get ids
	if @temp_table is null
		select distinct x.obj_id
		from objs_folders_details x
			join objs_folders f on f.folder_id = x.folder_id
				join @folders i on i.id = f.folder_id
		where 
            isnull(@obj_type, '') = 'all'
            or x.obj_type = isnull(@obj_type, f.obj_type)
	
	else begin
		 declare @sql nvarchar(max) = concat(N'insert into ', @temp_table,
			'
			select distinct x.obj_id
			from objs_folders_details x
				join objs_folders f on f.folder_id = x.folder_id
					join @folders i on i.id = f.folder_id
			where isnull(@obj_type, '''') = ''all''
                or x.obj_type = isnull(@obj_type, f.obj_type)
			'
			)
		declare @fields nvarchar(max) = '
			@obj_type varchar(16),
			@folders app_pkids readonly
			'
		exec sp_executesql @sql, @fields, @obj_type, @folders
	end
end
GO
