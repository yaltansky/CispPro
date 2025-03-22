if exists(select 1 from sys.objects where name = 'tasks_theme_move')
	drop procedure tasks_theme_move
go
create procedure tasks_theme_move
	@theme_id int,
	@target_id int = null,
	@where varchar(10) = 'into'
AS  
begin  
	
	exec tree_move_node 
		@table_name = 'tasks_themes',
		@key_name = 'theme_id',
		@source_id = @theme_id,
		@target_id = @target_id,
		@where = @where

end
go
