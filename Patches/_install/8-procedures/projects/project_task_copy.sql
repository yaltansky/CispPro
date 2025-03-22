if object_id('project_task_copy') is not null drop proc project_task_copy
go
create proc project_task_copy
	@source_id int,
	@target_id int
as
begin

	set nocount on;

	declare @project_id int = (select project_id from projects_tasks where task_id = @source_id)
	declare @source hierarchyid = (select node from projects_tasks where task_id = @source_id)

	declare @target_project_id int = (select project_id from projects_tasks where task_id = @target_id)
	
	declare @tasks table(task_id int primary key)

	declare @map table(source_id int primary key, target_id int index ix_target)
	insert into @map values(@source_id, @target_id)

BEGIN TRY
BEGIN TRANSACTION

	insert into @tasks(task_id)
		select task_id from projects_tasks
		where project_id = @project_id
			and node.IsDescendantOf(@source) = 1
			and task_id <> @source_id -- кроме самого узла
			and is_deleted = 0

-- clone all childs
	insert into projects_tasks(
		project_id, reserved, parent_id, has_childs, status_id, task_number, name, d_from, d_to, d_before, d_after, base_d_from, base_d_to, duration, duration_input, duration_id, predecessors, description, sort_id, priority_id, outline_level, tags, is_node
		)
		output inserted.reserved, inserted.task_id into @map
	select 
		@target_project_id, task_id, parent_id, has_childs, status_id, task_number, name, d_from, d_to, d_before, d_after, base_d_from, base_d_to, duration, duration_input, duration_id, predecessors, description, sort_id, priority_id, outline_level, tags, is_node
	from projects_tasks
	where task_id in (select task_id from @tasks)
	order by node

	update t2
	set name = '(копия) ' + t1.name,
		is_node = t1.is_node
	from projects_tasks t1, projects_tasks t2
	where t1.task_id = @source_id
		and t2.task_id = @target_id

-- update parents
	update t
	set parent_id = m.target_id
	from projects_tasks t
		join @map m on m.source_id = t.parent_id
	where t.task_id in (select target_id from @map)

-- copy links
	insert into projects_tasks_links(project_id, source_id, target_id, type_id)
	select @target_project_id, isnull(m1.target_id, l.source_id), isnull(m2.target_id, l.target_id), l.type_id
	from projects_tasks_links l
		left join @map m2 on m2.source_id = l.target_id
		left join @map m1 on m1.source_id = l.source_id
	where not (l.source_id in (select source_id from @map) and l.target_id not in (select source_id from @map))
		and (l.source_id in (select source_id from @map) or l.target_id in (select source_id from @map))

-- copy resources
	insert into projects_tasks_resources(task_id, resource_id, quantity, mol_id, note, add_date)
	select m.target_id, resource_id, quantity, mol_id, note, getdate()
	from projects_tasks_resources r
		join @map m on m.source_id = r.task_id

-- copy budgets
	insert into projects_tasks_budgets(project_id, budget_id, task_id, article_id, plan_bdr, plan_dds, note, mol_id)
	select @target_project_id, r.budget_id, m.target_id, r.article_id, plan_bdr, plan_dds, note, mol_id
	from projects_tasks_budgets r
		join @map m on m.source_id = r.task_id

-- reorder tasks	
	exec project_tasks_reorder @project_id = @target_project_id, @calctree = 1

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max) = error_message()
	raiserror (@err, 16, 1)
END CATCH

end
GO
