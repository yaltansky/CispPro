if object_id('sys_query_insert') is not null drop function sys_query_insert
go
create function sys_query_insert (
	@table sysname,
	@params varchar(max),
	@exclude varchar(max),
	@source_prefix varchar(50),
	@alias varchar(50),
	@identity bit
) returns nvarchar(max) as
begin

	declare @columns table (id int, name sysname)

	insert into @columns
	select 
		row_number() over(order by c.name)
		, c.name  as field
	from syscolumns c
	where id = object_id(@table)
		and c.iscomputed = 0
		and c.name not in (select item from dbo.str2rows(@exclude, ','))

	declare @insert_columns varchar(max) = (
		select 
			case when id > 1 then ', ' end as [text()],
			'[' + name + ']' as [text()]
		from @columns
		for xml path('')
		)

	declare @select_columns varchar(max) = (
		select 
			case when id > 1 then ', ' end as [text()],
			case 
				when charindex(name, @params) > 0 then '@' + name
				else isnull(@alias + '.', '') + '[' + name + ']'
			end as [text()]
		from @columns
		for xml path('')
		)
	
	return concat(
		case when @identity = 1 then concat('SET IDENTITY_INSERT ', @table, ' ON; ', CHAR(10)) end,
			'INSERT INTO ', @table, '(', @insert_columns, ')',CHAR(10),
			'SELECT ', @select_columns, CHAR(10),
			'FROM ', @source_prefix, @table, ' ', @alias,  CHAR(10),
		case when @identity = 1 then concat('SET IDENTITY_INSERT ', @table, ' OFF; ', CHAR(10)) end
		)
end
GO
