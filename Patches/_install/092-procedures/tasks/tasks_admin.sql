if object_id('tasks_admin') is not null drop proc tasks_admin
go
create proc [tasks_admin]
as
begin

	set nocount on;

	-- удалить пустые комментарии
	delete from tasks_hists 
	where description is null and body is null
		and action_name = 'Комментировать'

	-- актуализировать аудиторов
	insert into tasks_mols(task_id, role_id, mol_id)
	select t.task_id, 20, tm.mol_id
	from tasks t
		inner join tasks_themes_mols tm on tm.theme_id = t.theme_id
	where not exists(select 1 from tasks_mols where task_id = t.task_id and role_id = 20 and mol_id = tm.mol_id)

end
GO
