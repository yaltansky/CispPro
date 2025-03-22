if object_id('trees_calc') is not null drop procedure trees_calc
go
create procedure trees_calc
	@type_id int = 1
as
begin

-- sync with source
	if @type_id = 1
	begin
		-- delete lost refs
		delete from trees where type_id = 1
			and obj_type = 'PRJ'
			and obj_id in (select project_id from projects where status_id = -1)
		-- update names
		update trees 
		set name = p.name
		from trees
			inner join projects p on p.project_id = trees.obj_id
		-- append news
		insert into trees(type_id, name, obj_type, obj_id)
		select 1, name, 'PRJ', project_id from projects
		where project_id not in (select obj_id from trees where type_id = 1 and obj_id is not null)
			and status_id not in (-1, 0, 10)
			and type_id = 1
	end

-- hierarchyid
	declare @where_rows varchar(100) = 'type_id = ' + cast(@type_id as varchar)
	exec tree_calc_nodes 'trees', 'tree_id', @where_rows = @where_rows, @sortable = 0
end
GO
