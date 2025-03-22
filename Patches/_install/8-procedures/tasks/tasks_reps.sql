if object_id('tasks_reps') is not null drop proc tasks_reps
go
-- exec tasks_reps 700, 13915
create proc tasks_reps
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'tsk'

	select
		task_hid = concat('#', x.task_id),
		type_name = types.name,
		theme_name = isnull(themes.name, ''),
		project_name = prj.name,
		x.title,
		status_name = ts.name,
		d_doc_month = concat('месяц ', datepart(month, x.d_deadline)),
		d_doc_week = concat('неделя ', datepart(iso_week, x.d_deadline)),
		x.d_doc,
		d_deadline = isnull(tm.d_deadline, x.d_deadline),
		h.d_hist,
		x.d_closed,
		author_name = m1.name,
		analyzer_name = m2.name,
		executor_name = m3.name
	from tasks x
		join @ids i on i.id = x.task_id
		join tasks_statuses ts on ts.status_id = x.status_id
		left join tasks_types types on types.type_id = x.type_id
		left join tasks_themes themes on themes.theme_id = x.theme_id		
		left join projects_tasks pt on pt.task_id = x.project_task_id
			left join projects prj on prj.project_id = pt.project_id
		left join mols m1 on m1.mol_id = x.author_id
		left join mols m2 on m2.mol_id = x.analyzer_id
		left join tasks_mols tm on tm.task_id = x.task_id and tm.role_id = 1 -- исполнители
			left join mols m3 on m3.mol_id = tm.mol_id
		left join (
			select task_id, max(d_add) as d_hist
			from tasks_hists
			group by task_id
		) h on h.task_id = x.task_id

end
GO
