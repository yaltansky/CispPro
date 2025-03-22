if object_id('projects_pivots_tasks') is not null drop proc projects_pivots_tasks
go
-- exec projects_pivots_tasks 1000, -1
create proc projects_pivots_tasks
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

-- @ids
	declare @ids as app_pkids
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'prj'

-- select
	select
		MOL_NAME = M.NAME,
		PROJECT_NAME = P.NAME,
		T.TASK_NUMBER,
		TASK_NAME = concat(
			left('                                                            ', 6 * (t.node.GetLevel()-1)),
			t.name
			),
		RACI = isnull(r.raci ,''),
		T.D_FROM,
		T.D_TO,
		T.D_TO_FACT,
		PROGRESS = isnull(t.progress,0),
		STATUS_NAME = case when t.progress = 1 then 'Закрыто' else 'Открыто' end
	from projects_tasks t
		join projects p on p.project_id = t.project_id
		left join projects_tasks_raci r on r.task_id = t.task_id	
			left join mols m on m.mol_id = r.mol_id
	where p.project_id in (select id from @ids)

end
go
