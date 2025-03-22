if object_id('sys_columns') is not null drop function sys_columns
GO
create function sys_columns (
	@table sysname,
	@declaration bit,
	@prefix nvarchar(50),
	@exclude nvarchar(max)
) returns nvarchar(max) as
begin

	declare @columns table (id int, name sysname, declaration sysname)

	insert into @columns
	select 
		row_number() over(order by c.colorder)
		, c.name  as field
		, '[' + c.name + '] ' 
			+ '[' + case when t.name = 'decimal' then 'float' else t.name end + '] ' 
			+ case 
				when t.variable = 1 then 
					'(' + 
					case 
						when c.length = -1 then 'max'
						else cast(c.length as nvarchar)
					end
					+ ')' 
				else '' 
			  end 
			+ case when c.isnullable = 1 then ' NULL' else ' NOT NULL' end
	from syscolumns c
		join systypes t0 on c.xusertype = t0.xusertype
		join systypes t on c.xtype = t.xusertype
	where 
		id = object_id(@table)
		and c.iscomputed = 0
		and not c.name in (select item from dbo.str2rows(@exclude, ','))

	declare @res xml 
	set @res = (
		select 
			case when id > 1 then ', ' end as [text()],
			case when @declaration = 0 then isnull(@prefix + '.', '') + name else declaration end as [text()]
		from @columns
		for xml path('')
	)
	
	return cast(@res as nvarchar(max))

end
GO
