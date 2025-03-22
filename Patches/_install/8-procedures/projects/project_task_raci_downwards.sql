if object_id('project_task_raci_downwards') is not null drop proc project_task_raci_downwards
go

create proc project_task_raci_downwards
	@mol_id int,
	@task_id int
as
begin

	set nocount on;

	declare @project_id int, @node hierarchyid
	select @project_id = project_id, @node = node from projects_tasks where task_id = @task_id

	declare @tasks table(task_id int primary key)
		insert into @tasks(task_id)
		select task_id 
		from projects_tasks 
		where project_id = @project_id
			and node.IsDescendantOf(@node) = 1
			and task_id <> @task_id

-- delete RACI
	delete from projects_tasks_raci
	where task_id in (select task_id from @tasks)

-- insert RACI (clone)
	insert into projects_tasks_raci(task_id, mol_id, raci)
	select t.task_id, r.mol_id, r.raci
	from projects_tasks_raci r, @tasks t
	where r.task_id = @task_id

end
GO
