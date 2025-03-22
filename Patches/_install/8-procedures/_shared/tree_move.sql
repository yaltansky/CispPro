if exists(select 1 from sys.objects where name = 'tree_move')
	drop procedure tree_move
go
create procedure tree_move
	@tree_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  

	declare @type_id int = (select type_id from trees where tree_id = @tree_id)
	declare @where_rows varchar(100) = 'type_id = ' + cast(@type_id as varchar)
	declare @script_after_update varchar(1000) = '
		update p
		set folder_id = x.parent_id
		from projects p
			inner join trees x on x.type_id = 1 and x.obj_id = p.project_id
		where x.tree_id in (select id from @affected where id is not null)
	'

	exec tree_move_node 'trees', 'tree_id', @where_rows, @tree_id, @target_id, @where, @script_after_update

end
go
