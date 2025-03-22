if object_id('project_tasks_calc_predecessors') is not null drop proc project_tasks_calc_predecessors
go
create proc project_tasks_calc_predecessors
	@project_id int,
	@task_id int = null
as
begin

	set nocount on;

	update projects_tasks
	set predecessors = null
	where project_id = @project_id
		and predecessors is not null
		and (@task_id is null or task_id = @task_id)

	declare @links table(target_id int index ix_target, source_number varchar(30))
		insert into @links(target_id, source_number)
		select target_id, source_number	from v_projects_tasks_links
		where project_id = @project_id
			and (@task_id is null or target_id = @task_id)

	declare @predecessors table(target_id int primary key, predecessors varchar(2000))
		insert into @predecessors(target_id, predecessors)
		select distinct target_id,
			(
				select source_number + ';' as [text()]
				from @links where target_id = l2.target_id
				for xml path('')
			) predecessors
		from @links l2

	update x
	set predecessors = xx.predecessors
	from projects_tasks x
		join @predecessors xx on xx.target_id = x.task_id
	where x.project_id = @project_id

end
GO
