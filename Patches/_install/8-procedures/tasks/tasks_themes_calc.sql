if object_id('tasks_themes_calc') is not null
	drop proc tasks_themes_calc
go
create proc tasks_themes_calc
as
begin

	exec tree_calc_nodes 'tasks_themes', 'theme_id'

end
GO
