if object_id('objs_folder_notin') is not null drop proc objs_folder_notin
go
create proc objs_folder_notin
	@mol_id int,
	@folder_id int,
	@folderout_id int out
as
begin

	set nocount on;

-- initialize
	declare @folders_key varchar(50), @folder hierarchyid, @parent_id int
		select 
			@parent_id = parent_id,
			@folders_key = keyword,
			@folder = node 
		from objs_folders where folder_id = @folder_id

	declare @parent hierarchyid = (select node from objs_folders where folder_id = @parent_id)

-- @others_folder_id
	declare @others_folder_key varchar(50) = @folders_key + '-others-' + cast(@mol_id as varchar)
	declare @others_folder_id int = (select folder_id from objs_folders where keyword = @others_folder_key)

	if @others_folder_id is null begin
		insert into objs_folders(keyword, name, add_mol_id) values(@others_folder_key, @others_folder_key, @mol_id)
		set @others_folder_id = @@identity
	end

	set @folderout_id = @others_folder_id
	
-- clear virtual folder
	delete from objs_folders_details where folder_id = @folderout_id
	
-- @set
	declare @set app_pkids

	if @parent_id is null
	begin
		if @folders_key = 'DOGOVOR'
			insert into @set select document_id from documents where type_id = 2 and is_deleted = 0
		else if @folders_key = 'PAYORDER'
			insert into @set select payorder_id from payorders where status_id <> -1
	end
	
	else
	begin
		insert into @set 
			select distinct obj_id 
			from objs_folders_details fd
				inner join objs_folders f on f.folder_id = fd.folder_id
			where f.keyword = @folders_key
				and f.is_deleted = 0
				and f.node.IsDescendantOf(@parent) = 1
	end

-- @set2
	declare @set2 app_pkids
		insert into @set2
			select distinct obj_id 
			from objs_folders_details fd
				inner join objs_folders f on f.folder_id = fd.folder_id
			where f.keyword = @folders_key
				and f.is_deleted = 0
				and f.node.IsDescendantOf(@folder) = 1

-- @set - @set2
	delete x from @set x
		inner join @set2 x2 on x2.id = x.id
		
	insert into objs_folders_details(folder_id, obj_id, add_mol_id)
	select @folderout_id, id, @mol_id from @set

end
GO