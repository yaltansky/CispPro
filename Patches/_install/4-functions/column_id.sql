if object_id('column_id') is not null drop function column_id
go
create function column_id (
	@column_path sysname -- example: 'dbo.SOME_TABLE_NAME.SOME_COLUMN_NAME'
) returns int as
begin

	declare @path table(item sysname, id int identity)
	insert into @path select item from dbo.str2rows(@column_path, '.')

	declare @table_name sysname = (select item from @path order by id desc offset 1 rows fetch next 1 rows only)
	declare @column_name sysname = (select item from @path order by id desc offset 0 rows fetch next 1 rows only)

	return (
		select column_id from sys.columns where object_id = object_id(@table_name) and name = @column_name
		)

end
GO
