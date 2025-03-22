if object_id('mfr_plan_jobs_autofolder') is not null drop proc mfr_plan_jobs_autofolder
go
create proc mfr_plan_jobs_autofolder
	@ftype_id int, -- 1 - Создано, 2 - Закрыто
	@jobs app_pkids readonly,
	@d_doc date = null
as
begin

  	set nocount on;

	-- @root_id
		declare @root_id int = (select top 1 folder_id from objs_folders where keyword = 'mfj' and name = '#ЖурналСЗ')
		if @root_id is null
		begin
			insert into objs_folders(keyword, name, add_mol_id) values('mfj', '#ЖурналСЗ', 0)
			set @root_id = @@identity
		end
	
	-- @date_id
		declare @today date = isnull(@d_doc, dbo.today())
		declare @todayname varchar(10) = convert(varchar(10), @today, 20)
		declare @date_id int = (select folder_id from objs_folders where parent_id = @root_id and name = @todayname)
		if @date_id is null
		begin
			insert into objs_folders(keyword, parent_id, name, add_mol_id) values('mfj', @root_id, @todayname, 0)
			set @date_id = @@identity
		end

	-- @ftype_id
		declare @fname varchar(50) = 
			case
				when @ftype_id = 1 then '1-Создано'
				when @ftype_id = 2 then '2-Закрыто'
				else concat('undefined type', @ftype_id)
			end

		declare @folder_id int = (select top 1 folder_id from objs_folders where parent_id = @date_id and name = @fname)
		if @folder_id is null
		begin
			insert into objs_folders(keyword, parent_id, name, add_mol_id) values('mfj', @date_id, @fname, 0)
			set @folder_id = @@identity
		end

	-- add @jobs
		delete x from objs_folders_details x
			join @jobs i on i.id = x.obj_id
		where folder_id = @folder_id and obj_type = 'mfj'

		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @folder_id, 'mfj', id, 0
		from @jobs
end
go
