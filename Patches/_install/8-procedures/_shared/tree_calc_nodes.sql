if object_id('tree_calc_nodes') is not null drop procedure tree_calc_nodes
go
create procedure tree_calc_nodes
	@table_name varchar(50),
	@key_name varchar(50),
	@where_rows nvarchar(250) = null,
	@sort_clause nvarchar(250) = null,
	@sortable bit = 0,
	@use_sort_id bit = 0,
	@trace bit = 0
as  
begin  
	set nocount on;

declare @sql nvarchar(max) = N'
-- hierarchyid
	declare @children tree_nodes
		insert @children (node_id, parent_id, num)
		select document_id, parent_id,  
		  row_number() over (partition by parent_id order by <order_by>)
		from documents where <where_rows> is_deleted = 0

	declare @nodes tree_nodes; insert into @nodes exec tree_calc @children

	update documents set node = null where <where_rows> is_deleted = 1

	if exists(
		select 1 from documents x
			join @nodes as xx on xx.node_id = x.document_id
		where isnull(x.node,''/'') <> isnull(xx.node, ''/'')
		)
	begin
		update x set node = xx.node <set_level_id>
		from documents x
			join @nodes as xx on xx.node_id = x.document_id
		where isnull(x.node,''/'') <> isnull(xx.node, ''/'')
	end

-- sort_id
	<stmt_sorting>

-- has_childs
	update x
	set has_childs = 
			case
				when exists(select 1 from documents where <where_rows> parent_id = x.document_id and is_deleted = 0) then 1
				else 0
			end
	from documents x
	where <where_rows> is_deleted = 0
'

set @sql = replace(@sql, '<stmt_sorting>', 
	case
		when @sortable = 1 or @use_sort_id = 1 then '
			update x
			set sort_id = xx.sort_id
			from documents x
				join (
					select document_id, row_number() over(order by node) as sort_id
					from documents
				) xx on xx.document_id = x.document_id
			where <where_rows> is_deleted = 0
			'
		else ''
	end
	)

set @sql = replace(@sql, '<set_level_id>', 
	case 
		when exists(select 1 from sys.columns where name = 'level_id' and object_name(object_id) = @table_name) then
			', level_id = xx.level_id'
		else ''
	end
	)

set @sql = replace(@sql, 'documents', @table_name)
set @sql = replace(@sql, 'document_id', @key_name)
set @sql = replace(@sql, '<where_rows>', isnull(@where_rows + ' and ', ''))
set @sql = replace(@sql, '<order_by>', 
	case 
		when @sortable = 1 then 'parent_id, node, sort_id, name'
		else isnull(@sort_clause, 'parent_id, has_childs desc, name')
	end)

if @trace = 1 print @sql
exec sp_executesql @sql

end
go
