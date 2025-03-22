if object_id('objs_folders_view') is not null drop proc objs_folders_view
go
-- exec objs_folders_view 1000, @keyword = 'MFR', @search = '#57729'
create proc objs_folders_view
	@mol_id int,
	@keyword varchar(30),
	@root_id int = null,
	@parent_id int = null,
	@search varchar(50) = null,
	@obj_type varchar(16) = null,
	@obj_id int = null,
	@ids varchar(max) = null,
	@show_deleted bit = 0
as
begin
	
	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin')

	declare @root hierarchyid = (select node from objs_folders where folder_id = @root_id)
	declare @buffer_id int = (select top 1 folder_id from objs_folders where add_mol_id = @mol_id and keyword = 'buffer')
	declare @folder_id int, @folder hierarchyid

	declare @result table(folder_id int, node hierarchyid)
	declare @folder_ids table(id int)
	
	-- @search
	if dbo.hashid(@search) is not null
	begin
		declare @node hierarchyid = (select node from objs_folders where folder_id = dbo.hashid(@search))
		-- + all parents
		insert into @folder_ids select folder_id from objs_folders
		where keyword = @keyword and  @node.IsDescendantOf(node) = 1

		set @search = null
	end

	if @ids is not null
		insert into @folder_ids select distinct item from dbo.str2rows(@ids, ',')

	if @show_deleted = 1
		insert into @result(folder_id)
		select folder_id
		from objs_folders
		where keyword = @keyword
			and is_deleted = 1
			and (@search is null or name like '%' + @search + '%')
	
	else if exists(select 1 from @folder_ids)
	begin
		-- parents
		insert into @result(folder_id) select id from @folder_ids

		-- + childs
		insert into @result(folder_id)
		select x.folder_id
		from objs_folders x
			join @result xx on xx.folder_id = x.parent_id

		-- + root
		insert into @result(folder_id)
		select folder_id from objs_folders
		where keyword = @keyword 
			and isnull(parent_id,0) = isnull(@root_id,0)
	end

	else if @parent_id is not null or @search is null
		insert into @result(folder_id)
		select folder_id
		from objs_folders
		where keyword = @keyword
			and isnull(parent_id,0) = coalesce(@parent_id, @root_id, 0)
			and is_deleted = 0

	else
	begin

		if @search like '#buffer%'
		begin
			set @folder_id = try_parse(substring(@search, 9, 50) as int)
			set @folder = (select node from objs_folders where folder_id = @folder_id)
		
			insert into @result(folder_id, node)
			select f.folder_id, f.node
			from objs_folders f
			where f.keyword = @keyword
				and folder_id in (
						select d.folder_id
						from objs_folders_details d
							join objs_folders f on f.folder_id = d.folder_id
							join objs_folders_details b on b.obj_type = d.obj_type and b.obj_id = d.obj_id
						where f.keyword = @keyword
							and b.folder_id = @buffer_id
							and d.obj_type = @obj_type
						)
				and (@folder_id is null or f.node.IsDescendantOf(@folder) = 1)
				and f.is_deleted = 0
		end

		else if @search like '#dups:%'
		begin
			set @folder_id = try_parse(substring(@search, 7, 50) as int)
			set @folder = (select node from objs_folders where folder_id = @folder_id)
		
			declare @folders table(folder_id int primary key)
				insert into @folders(folder_id)
				select folder_id
				from objs_folders
				where keyword = @keyword
					and node.IsDescendantOf(@folder) = 1
					and is_deleted = 0
		
			delete from objs_folders_details where folder_id = @buffer_id

			declare @buffer table(obj_id int, obj_type varchar(16))

			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				output inserted.obj_id, inserted.obj_type into @buffer
			select @buffer_id, obj_type, obj_id, @mol_id
			from objs_folders_details
			where folder_id in (select folder_id from @folders)
			group by obj_type, obj_id
			having count(*) > 1

			insert into @result(folder_id, node)
			select distinct f.folder_id, f.node
			from objs_folders_details fd
				join objs_folders f on f.folder_id = fd.folder_id
				join @folders fs on fs.folder_id = fd.folder_id
				join @buffer b on b.obj_type = fd.obj_type and b.obj_id = fd.obj_id
			where b.obj_type = @obj_type
		end

		else if dbo.hashid(@search) is not null
		begin
			insert into @result(folder_id, node)
			select folder_id, node
			from objs_folders
			where folder_id = dbo.hashid(@search)

			-- insert into @result(folder_id, node)
			-- select folder_id, node
			-- from objs_folders
			-- where keyword = @keyword 
			-- 	and parent_id is null -- top level
			-- 	and is_deleted = 0
		end

		else begin
			set @search = '%' + replace(@search, ' ', '%') + '%'

			insert into @result(folder_id, node)
			select folder_id, node
			from objs_folders
			where keyword = @keyword
				and name like @search
				and is_deleted = 0
				and (@root_id is null or node.IsDescendantOf(@root) = 1)
		end

		-- parents
		insert into @result(folder_id)
		select distinct f.folder_id
		from objs_folders f
			join @result r on r.node.IsDescendantOf(f.node) = 1
		where f.keyword = @keyword
	end

-- final select
	select
		node_id = folder_id,
		x.folder_id,
		x.name,		
		x.status_id,
		--
		parent_id = case when @show_deleted = 0 then parent_id end,
		x.has_childs,
		x.level_id,
		x.sort_id,
		x.is_deleted,
		--
		x.counts,
		x.totals,
		x.keyword,
		x.obj_type,
		x.inherited_access,
		x.add_date,
		x.add_mol_id,
		x.update_date,
		x.update_mol_id
	from objs_folders x
	where folder_id in (select distinct folder_id from @result)
		and is_deleted in (0, @show_deleted)
		and (@root_id is null or node.IsDescendantOf(@root) = 1)
	order by node

end
GO
