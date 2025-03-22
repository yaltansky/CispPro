if object_id('objs_folders_compare') is not null drop proc objs_folders_compare
go

create proc objs_folders_compare
	@mol_id int,	
	@a varchar(max),
	@b varchar(max)
as
begin
	
	set nocount on;

	declare @foldersA table(folder_id int, node hierarchyid)
		insert into @foldersA(folder_id, node)
		select folder_id, node
		from objs_folders
		where folder_id in (	select item from dbo.str2rows(@a, ','))

	declare @keyword varchar(30) = (select top 1 keyword from OBJS_FOLDERS where folder_id in (select folder_id from @foldersA))

	declare @foldersB table(folder_id int, node hierarchyid)
		insert into @foldersB(folder_id, node)
		select folder_id, node
		from objs_folders
		where folder_id in (	select item from dbo.str2rows(@b, ','))

	create table #seta (obj_type varchar(16), obj_id int, 
		constraint pk_seta primary key (obj_type, obj_id)
		)
	
	create table #setb (obj_type varchar(16), obj_id int, 
		constraint pk_setb primary key (obj_type, obj_id)
		)

-- #seta	
	insert into #seta(obj_type, obj_id)
	select distinct obj_type, obj_id
	from objs_folders_details
	where folder_id in (
		select f.folder_id
		from objs_folders f
			join @foldersA x on f.node.IsDescendantOf(x.node) = 1
		where f.keyword = @keyword
      and f.is_deleted = 0
		)

-- #setab
	insert into #setb(obj_type, obj_id)
	select distinct obj_type, obj_id
	from objs_folders_details
	where folder_id in (
		select f.folder_id
		from objs_folders f
			join @foldersB x on f.node.IsDescendantOf(x.node) = 1
		where f.keyword = @keyword
      and f.is_deleted = 0
		)

-- A-B
	declare @result_folder_id int = (select top 1 folder_id from objs_folders where add_mol_id = @mol_id and keyword = 'compare' and name = 'Множество A - B')
		if @result_folder_id is null
		begin
			insert into objs_folders(add_mol_id, keyword, name) values(@mol_id, 'compare', 'Множество A - B')
			set @result_folder_id = @@identity
		end

	delete from objs_folders_details where folder_id = @result_folder_id
	
	insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
	select @result_folder_id, obj_type, obj_id, @mol_id
	from #seta

	delete x 
	from objs_folders_details x
		join #setb b on b.obj_type = x.obj_type and b.obj_id = x.obj_id
	where x.folder_id = @result_folder_id

-- B-A
	set @result_folder_id = (select top 1 folder_id from objs_folders where add_mol_id = @mol_id and keyword = 'compare' and name = 'Множество B - A')
		if @result_folder_id is null
		begin
			insert into objs_folders(add_mol_id, keyword, name) values(@mol_id, 'compare', 'Множество B - A')
			set @result_folder_id = @@identity
		end

	delete from objs_folders_details where folder_id = @result_folder_id
	
	insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
	select @result_folder_id, obj_type, obj_id, @mol_id
	from #setb

	delete x 
	from objs_folders_details x
		join #seta a on a.obj_type = x.obj_type and a.obj_id = x.obj_id
	where x.folder_id = @result_folder_id

-- A & B
	set @result_folder_id = (select top 1 folder_id from objs_folders where add_mol_id = @mol_id and keyword = 'compare' and name = 'Множество A & B')
		if @result_folder_id is null
		begin
			insert into objs_folders(add_mol_id, keyword, name) values(@mol_id, 'compare', 'Множество A & B')
			set @result_folder_id = @@identity
		end

	delete from objs_folders_details where folder_id = @result_folder_id
	
	insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
	select @result_folder_id, a.obj_type, a.obj_id, @mol_id
	from #seta a
		join #setb b on b.obj_type = b.obj_type and b.obj_id = a.obj_id

-- result
	select NODE_ID = FOLDER_ID, *
	from objs_folders
	where folder_id in (
		select folder_id
		from objs_folders
		where add_mol_id = @mol_id and keyword = 'compare'
		)

end
GO