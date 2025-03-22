if object_id('product_option_list') is not null drop proc product_option_list
go
create proc product_option_list
	@option_name varchar(50)
as
begin

	set nocount on;

	declare @sql nvarchar(250) = 'select distinct @column as name from products where isnull(@column,'''') <> '''''
	set @sql = replace(@sql, '@column', @option_name)

	exec sp_executesql @sql
end
go
