if object_id('project_tasks_calc_links') is not null drop proc project_tasks_calc_links
go
create proc [dbo].[project_tasks_calc_links]
	@project_id int,
	@target_id int = null
as
begin

	set nocount on;

	-- validate for @target_id
	if @target_id is not null
	begin
		create table #check(task_id int)
		insert into #check(task_id)
		select distinct s.item
		from projects_tasks t
			cross apply dbo.str2rows(t.predecessors, ';') s
		where task_id = @target_id
			and isnumeric(s.item) = 1

		;with s as (
			select source_id, target_id from projects_tasks_links where target_id in (select task_id from #check)
			union all
			select l.source_id, l.target_id
			from projects_tasks_links l
				inner join s on s.target_id = l.source_id
			)
			insert into #check(task_id)
			select distinct source_id from s

		if exists(select 1 from #check where task_id = @target_id)
		begin
			update projects_tasks
			set predecessors = 'ОШИБКА(циклические ссылки);' + predecessors
			where task_id = @target_id
				and predecessors not like 'ОШИБКА(циклические ссылки)%'

			raiserror('Есть циклические ссылки для задачи (код %d). Необходимо изменить предшественников у задачи.', 16, 1, @target_id)
			return
		end
	end

	delete from projects_tasks_links where project_id = @project_id
		and (@target_id is null or target_id = @target_id)

	insert into projects_tasks_links(project_id, source_id, target_id)
	select pp.project_id, ps.task_id, pp.task_id
	from projects_tasks pp
		cross apply dbo.str2rows(pp.predecessors, ';') s
		inner join projects_tasks ps on ps.project_id = pp.project_id and ps.task_number = s.item
	where pp.project_id = @project_id
		and (@target_id is null or pp.task_id = @target_id)
		and ps.task_id <> pp.task_id

end
GO
