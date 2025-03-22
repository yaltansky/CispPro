if object_id('objs_folder_path') is not null drop proc objs_folder_path
go
create proc objs_folder_path
	@folder_id int,
	@path varchar(max) out 
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @parents table (folder_id int index ix_folder, name varchar(250), level_id int)
	declare @level int = 1, @max_level int = 100
	
	while @folder_id is not null
		and @level < @max_level
	begin		
		insert into @parents(folder_id, name, level_id)
		select folder_id, name, node.GetLevel()
		from objs_folders d 
		where folder_id = @folder_id
										
		declare @parent_id int = (select parent_id from objs_folders where folder_id = @folder_id)
		
		if isnull(@parent_id,0) <> @folder_id 
			and not exists(select 1 from @parents where folder_id = isnull(@parent_id,0))
			set @folder_id = @parent_id
		
		else begin
			set @level = @max_level
			print 'Цепочка папок содержит циклические ссылки. Необходимо это устранить.'
		end

		set @level = @level + 1
	end

	select @path = isnull(@path,'') 
		+ case when @path is null then '' else ' > ' end
		+ name
	from @parents
	order by level_id

	if @level >= @max_level set @path = '?' + @path
end
GO
