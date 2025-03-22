if object_id('products_builder') is not null drop proc products_builder
go
create proc products_builder
	@mol_id int,
	@source_name sysname,
	@source_key sysname,
	@item_name sysname,
	@obj_type varchar(16),
	@allproducts bit = 0
as
begin
	declare @cachetable varchar(50); exec products_builder;2 @mol_id, @cachetable out
	
	declare @sql nvarchar(max) = '
		truncate table [@cachetable];
		
		; -- build cachtable
		if @allproducts = 0
			insert into [@cachetable](product_id)
			select distinct x.[@item_name]
			from [@source] x
				join dbo.objs_buffer([@mol_id], ''[@obj_type]'') i on i.id = x.[@source_key]
		else
			insert into [@cachetable](product_id) values(-1)
					
		; -- mirror of cachtable in PP-buffer
		delete from objs_folders_details where folder_id = [@buffer_id] and obj_type = ''PP''
		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select [@buffer_id], ''PP'', product_id, [@mol_id] from [@cachetable]

		-- purge helper-buffer
		delete from objs_folders_details where folder_id = [@buffer_id] and obj_type = ''[@obj_type]''
		'		
	set @sql = replace(@sql, '[@cachetable]', @cachetable)
	set @sql = replace(@sql, '[@mol_id]', @mol_id)
	set @sql = replace(@sql, '[@source]', @source_name)
	set @sql = replace(@sql, '[@source_key]', @source_key)
	set @sql = replace(@sql, '[@item_name]', @item_name)
	set @sql = replace(@sql, '[@obj_type]', @obj_type)
	set @sql = replace(@sql, '[@buffer_id]', dbo.objs_buffer_id(@mol_id))
	set @sql = replace(@sql, '@allproducts', @allproducts)
	
	exec sp_executesql @sql
end
go
-- helper: cache table name
create proc products_builder;2 @mol_id int, @name varchar(50) = null out
as
begin
	set @name = concat('tmp_products', @mol_id)		

	declare @sql nvarchar(max)
			
	if object_id(@name) is null
	begin
		set @sql = replace('
	create table @products_cache(
		product_id int primary key,
		a_col1 nvarchar(255),
		a_col2 nvarchar(255),
		a_col3 nvarchar(255),
		a_col4 nvarchar(255),
		a_col5 nvarchar(255),
		a_col6 nvarchar(255),
		a_col7 nvarchar(255),
		a_col8 nvarchar(255),
		a_col9 nvarchar(255),
		a_col10 nvarchar(255),
		sort_id int
	)
	', '@products_cache', @name)

		exec sp_executesql @sql
	end
end
go
