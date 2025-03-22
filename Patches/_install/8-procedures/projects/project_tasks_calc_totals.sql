if object_id('project_tasks_calc_totals') is not null drop proc project_tasks_calc_totals
go
create proc [dbo].[project_tasks_calc_totals]
	@project_id int = null
as
begin

	set nocount on;

	-- #plan
	if @project_id is not null
	begin
		create table #plan (
			task_id int primary key
			, parent_id int			
			, has_childs bit
			, outline_level int
			, d_from datetime
			, d_to datetime
			, duration int
			, progress decimal(18,2)
			, count_checks int
			, count_checks_all int
			)	

		insert into #plan(task_id, parent_id, has_childs, outline_level, d_from, d_to, progress, duration, count_checks, count_checks_all)
			select task_id, parent_id, has_childs, outline_level, d_from, d_to, progress, duration, count_checks, count_checks_all 
			from projects_tasks
			where project_id = @project_id
	end

	declare @level int; set @level = (select max(outline_level) from #plan)

	-- terminal tasks
	declare @tasks table (parent_id int, task_id int primary key, outline_level int)

	insert into @tasks (parent_id, task_id, outline_level)
	select parent_id, task_id, outline_level from #plan
	where task_id not in (select parent_id from #plan where parent_id is not null)

	declare @update table (task_id int)

	-- iterations
	declare @next table (parent_id int, task_id int primary key, outline_level int)
	insert into @next (parent_id, task_id, outline_level)
	select parent_id, task_id, outline_level from @tasks
	where outline_level = @level -- last level
	
	-- обнулить сроки суммарных задач
	update #plan set d_from = null, d_to = null where has_childs = 1

	while exists(select 1 from @next)
		-- ... or exceeds limit loops
		and @level > 1 -- 1-й уровень - самый верхний
	begin
		-- update #plan
		update p		
		set d_from = c.d_from,
			d_to =	 c.d_to,
			duration = (select count(*) from calendar where day_date between c.d_from and c.d_to and type = 0),
			progress = c.progress,
			count_checks = c.count_checks,
			count_checks_all = c.count_checks_all

		output inserted.task_id into @update

		from #plan p
			inner join (
				select t.parent_id as task_id
					, min(c.d_from) as d_from
					, max(c.d_to) as d_to
					, 
						case
							when sum(c.duration) > 0 then sum(c.duration * isnull(c.progress,0)) / sum(c.duration) 
							else 0
						end as progress
					, sum(c.count_checks) as count_checks
					, sum(c.count_checks_all) as count_checks_all					
				from @next t
						inner join #plan c on c.task_id = t.task_id
				group by t.parent_id
			) c on c.task_id = p.task_id

		-- append previous level
		insert into @tasks(parent_id, task_id, outline_level)
		select parent_id, task_id, outline_level
		from #plan
		where task_id in (select task_id from @update)
			and task_id not in (select task_id from @tasks)

		-- next level
		set @level = @level - 1

		delete from @next;
		insert into @next (parent_id, task_id, outline_level)
		select parent_id, task_id, outline_level from @tasks
		where outline_level = @level
	end

	-- final update
	if @project_id is not null
		update t
		set d_from = #plan.d_from, d_to = #plan.d_to,
			duration = #plan.duration,
			progress = #plan.progress,
			count_checks = #plan.count_checks,
			count_checks_all = #plan.count_checks_all			
		from projects_tasks t
			inner join #plan on #plan.task_id = t.task_id
		where t.has_childs = 1

	-- calc outlines
	exec project_tasks_calc_totals;2 @project_id = @project_id
end
GO

create proc [dbo].[project_tasks_calc_totals];2
	@project_id int
as
/*
** Calc tasks outlines
*/
begin

	create table #tasks (
		task_id int primary key
		, parent_id int
		)	

	insert into #tasks(parent_id, task_id)
	select parent_id, task_id from projects_tasks where project_id = @project_id

	;with s as (
		select parent_id, task_id, 1 as level_id from #tasks where parent_id is null
		union all
		select t.parent_id, t.task_id, s.level_id + 1
		from #tasks t
			inner join s on s.task_id = t.parent_id
		)
		update t
		set outline_level = s.level_id
		from projects_tasks t
			inner join s on s.task_id = t.task_id

end
go
