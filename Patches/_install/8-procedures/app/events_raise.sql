if object_id('events_raise') is not null drop proc events_raise
go
create proc events_raise
as
begin

	set nocount on;

	declare @tid int; exec tracer_init 'events_raise', @trace_id = @tid out
		-- select * from trace_log where trace_name = 'events_raise'
	
	-- projects
	exec events_raise;20 @trace_id = @tid -- завершённые операции проекта
	exec events_raise;21 @trace_id = @tid -- свдвиг критических операциё проекта

	-- projects.RACI
	exec events_raise;22 @trace_id = @tid -- операции этой недели
	exec events_raise;23 @trace_id = @tid -- просроченные операции
	exec events_raise;24 @trace_id = @tid -- просроченные операции (эскалация)
	exec events_raise;25 @trace_id = @tid -- просроченные отчёты по рискам
	
	-- tasks
	exec events_raise;30 @trace_id = @tid -- задачи этой недели
	exec events_raise;31 @trace_id = @tid -- просроченные задачи
	exec events_raise;32 @trace_id = @tid -- просроченные задачи (эскалация)

	exec tracer_close @tid
end
go
-- завершённые операции проекта
create proc [dbo].[events_raise];20
	@trace_id int
as
begin

	if @trace_id is not null and datepart(weekday, getdate()) in (1,7)
	begin
		exec tracer_log @trace_id, 'завершённые операции проекта (не запущен, расписание: рабочие дни)'
		return -- nothing todo
	end
		
	exec tracer_log @trace_id, 'завершённые операции проекта (расписание: рабочие дни)'

	declare @tasks table (project_id int, task_id int)
	declare @report_date datetime = dbo.today() - 1
	declare @cr varchar(2) = char(10)
	declare @cr2 varchar(2) = char(10) + char(13)

	-- group by project
	insert into @tasks(project_id, task_id)
		select project_id, task_id from projects_tasks 
		where dbo.getday(d_progress_completed) = @report_date
			and status_id <> -1
			
	declare @result table(project_id int, content varchar(max))
	
	insert into @result(project_id, content) 
	select u.project_id, 
		'Проект "' + projects.name + '"'  + '.' + @cr2 +
		'Вчера завершены следующие операции:' + @cr
	from (
		select distinct project_id from @tasks
		) u
		inner join projects on projects.project_id = u.project_id

	update r
	set content = content + (
			select '    - ' + title + ' (' + cast(cast(duration as int) as varchar) + ' дн)' + ';' as [text()]
			from (
				select t.project_id, t.task_id, cast(t.task_number as varchar) + '.' + t.name as title, t.duration
				from @tasks tt
					inner join projects_tasks t on t.task_id = tt.task_id						
				where t.project_id = r.project_id
					and t.status_id <> -1
				) m
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', @cr)

	declare @events table(event_id int, project_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		2, -- projects
		1, -- ProjectTaskCompleted
		null, -- priority_id
		1, -- status_id
		'Завершение задач проекта',
		content,
		project_id
	from @result

	update events
	set href = 'projects/' + reserved + '/plan?EVENT_ID=' + cast(event_id as varchar)
	where event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
		select distinct event_id, mol_id
		from (
			select event_id, chief_id as mol_id from @events e
				inner join projects p on p.project_id = e.project_id
			union select event_id, admin_id from @events e
				inner join projects p on p.project_id = e.project_id			
			union select event_id, 700 from @events e -- DEBUG
			) u
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'PTS', task_id	
	from (
		select e.event_id, t.task_id from @events e, @tasks t where t.project_id = e.project_id
		) u
end
go
-- сдвиг критических операций проекта
create proc [dbo].[events_raise];21
	@trace_id int
as
begin
	
	declare @today datetime = dbo.today()

	if @trace_id is not null and datepart(weekday, getdate()) in (1,7)
	begin
		exec tracer_log @trace_id, 'сдвиг критических операций проекта (не запущен, расписание: рабочие дни)'
		return -- nothing todo
	end
		
	exec tracer_log @trace_id, 'сдвиг критических операций проекта (расписание: рабочие дни)'
	
	declare @tasks table (row_id int identity primary key, project_id int, task_id int)
	declare @cr varchar(2) = char(10)
	declare @cr2 varchar(2) = char(10) + char(13)
	
	-- group by project
	insert into @tasks(project_id, task_id)
		select project_id, task_id from projects_tasks
		where has_childs = 0 and is_critical = 1 and d_to > d_to_previous
			and status_id <> -1
			and d_from <= @today 
		order by project_id, task_number

	declare @result table(project_id int, content varchar(max))
	
	insert into @result(project_id, content) 
	select u.project_id, 
		'Проект "' + projects.name + '".'  + @cr2 +
		'Зафиксирован сдвиг критических операций:' + @cr
	from (
		select distinct project_id from @tasks
		) u
		inner join projects on projects.project_id = u.project_id

	update r
	set content = content + (
			select '    - ' + title + ' (сдвиг на ' + cast(cast(d_to_diff as int) as varchar) + ' дн)' + ';' as [text()]
			from (
				select t.project_id, t.task_id, cast(t.task_number as varchar) + '.' + t.name as title,
					datediff(d, t.d_to_previous, t.d_to) as d_to_diff
				from @tasks tt
					inner join projects_tasks t on t.task_id = tt.task_id
				where t.project_id = r.project_id				
					and t.status_id <> -1
				) m
			for xml path('')			
			)
	from @result r

	update @result set content = replace(content, ';', @cr)

	declare @events table(event_id int, project_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		2, -- projects
		3, -- ProjectTaskShift
		2, -- priority_id
		1, -- status_id
		'Сдвиг сроков проекта',
		content,
		project_id
	from @result

	update events
	set href = 'projects/' + reserved + '/plan?EVENT_ID=' + cast(event_id as varchar)
	where event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
		select distinct event_id, mol_id
		from (
			select event_id, chief_id as mol_id from @events e
				inner join projects p on p.project_id = e.project_id
			union select event_id, admin_id from @events e
				inner join projects p on p.project_id = e.project_id			
			union select event_id, 700 from @events e -- DEBUG
			) u
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'PTS', task_id	
	from (
		select e.event_id, t.task_id from @events e, @tasks t where t.project_id = e.project_id
		) u

	-- сохранить D_TO_PREVIOUS
	update projects_tasks set d_to_previous = d_to
	where has_childs = 0 and is_critical = 1
end
go
-- операции этой недели
create proc [dbo].[events_raise];22
	@trace_id int
as
begin

	if @trace_id is not null and datepart(weekday, getdate()) <> 2
	begin
		exec tracer_log @trace_id, 'операции этой недели (не запущен, расписание: пн)'
		return -- nothing todo
	end
		
	exec tracer_log @trace_id, 'операции этой недели (расписание: пн)'

	declare @today datetime = dbo.today()
	declare @week_start datetime = dbo.week_start(@today)
	declare @week_end datetime = @week_start + 6
	declare @cr varchar(2) = char(10)
	declare @cr2 varchar(2) = char(10) + char(13)

-- Срок наступает на этой неделе
	declare @tasks table (project_id int, task_id int, mol_id int)

	-- group by project
	insert into @tasks(project_id, task_id, mol_id)
		select t.project_id, t.task_id, raci.mol_id
			from projects_tasks t
				inner join projects_tasks_raci raci on raci.task_id = t.task_id and charindex('A', raci.raci) >= 1
		where t.d_to between @week_start and @week_end
			and t.has_childs = 0
			and t.progress < 1
			and t.status_id <> -1

	declare @result table(
		result_id int identity primary key
		, project_id int, mol_id int, content varchar(max))
	
	insert into @result(project_id, mol_id, content) 
	select u.project_id, u.mol_id,
		'Проект "' + projects.name + '"'  + '.' + @cr2 +
		'Операции со сроком реализации на этой неделе:' + @cr
	from (
		select distinct project_id, mol_id from @tasks
		) u
		inner join projects on projects.project_id = u.project_id

	update r
	set content = content + (
			select '    - ' + title + ' ' + ltrim(title) + ' (через ' + cast(datediff(d, @today, d_to) as varchar) + ' дн)' + ';' as [text()]
			from (
				select t.project_id, t.task_id, cast(t.task_number as varchar) + '.' + t.name as title, t.d_to
				from @tasks tt
					inner join projects_tasks t on t.task_id = tt.task_id						
				where t.project_id = r.project_id
					and t.status_id <> -1
					and tt.mol_id = r.mol_id
				) m
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', @cr)

	declare @events table(event_id int, result_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		2, -- projects
		8, -- ProjectTaskThisWeek
		null, -- priority_id
		1, -- status_id
		'Операции текущей недели',
		content,
		result_id
	from @result

	update e
	set href = 'projects/' + cast(r.project_id as varchar) + '/plan?EVENT_ID=' + cast(e.event_id as varchar)
	from events e
		inner join @result r on r.result_id = e.reserved
	where e.event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
		select distinct event_id, mol_id
		from (
			select e.event_id, r.mol_id from @events e
				inner join @result r on r.result_id = e.result_id
			union select event_id, 700 from @events e -- DEBUG
			) u
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'PTS', task_id	
	from (
		select e.event_id, t.task_id 
		from @events e
			join @result r on r.result_id = e.result_id
			join @tasks t on t.project_id = r.project_id and t.mol_id = r.mol_id
		) u
end
go
-- просроченные операции
create proc [dbo].[events_raise];23
	@trace_id int	
as
begin

	-- Понедельник, Среда
	if @trace_id is not null and datepart(weekday, getdate()) not in (2,4)
	begin
		exec tracer_log @trace_id, 'просроченные операции (не запущен, расписание: пн,ср)'
		return -- nothing todo
	end
		
	exec tracer_log @trace_id, 'просроченные операции (расписание: пн, ср)'

	declare @tasks table (project_id int, task_id int, mol_id int)
	declare @today datetime = dbo.today()

	-- group by project
	insert into @tasks(project_id, task_id, mol_id)
		select t.project_id, t.task_id, raci.mol_id
			from projects_tasks t
				inner join projects_tasks_raci raci on raci.task_id = t.task_id and charindex('A', raci.raci) >= 1
		where t.d_before < @today
			and t.has_childs = 0
			and t.progress < 1
			and t.status_id <> -1

	declare @result table(
		result_id int identity primary key
		, project_id int, mol_id int, content varchar(max))
	
	insert into @result(project_id, mol_id, content) 
	select u.project_id, u.mol_id,
		'Проект "' + projects.name + '"'  + '.' + char(10) + char(13) +
		'Просроченные операции:' + char(10)
	from (
		select distinct project_id, mol_id from @tasks
		) u
		inner join projects on projects.project_id = u.project_id

	update r
	set content = content + (
			select '    - ' + title + ' ' + ltrim(title) + ' (просрочено ' + cast(datediff(d, @today, d_before) as varchar) + ' дн)' + ';' as [text()]
			from (
				select t.project_id, t.task_id, cast(t.task_number as varchar) + '.' + t.name as title, t.d_before
				from @tasks tt
					inner join projects_tasks t on t.task_id = tt.task_id						
				where t.project_id = r.project_id
					and t.status_id <> -1
					and tt.mol_id = r.mol_id
				) m
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', char(10))

	declare @events table(event_id int, result_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		2, -- projects
		9, -- ProjectTaskOverdue
		null, -- priority_id
		1, -- status_id
		'Просроченные операции',
		content,
		result_id
	from @result

	update e
	set href = 'projects/' + cast(r.project_id as varchar) + '/plan?EVENT_ID=' + cast(e.event_id as varchar)
	from events e
		inner join @result r on r.result_id = e.reserved
	where e.event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
		select distinct event_id, mol_id
		from (
			select e.event_id, r.mol_id from @events e
				inner join @result r on r.result_id = e.result_id
			union select event_id, 700 from @events e -- DEBUG
			) u
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'PTS', task_id	
	from (
		select e.event_id, t.task_id 
		from @events e
			join @result r on r.result_id = e.result_id
			join @tasks t on t.project_id = r.project_id and t.mol_id = r.mol_id
		) u
end
go
-- просроченные операции (эскалация)
create proc [dbo].[events_raise];24
	@trace_id int	
as
begin

	-- Пятница
	if @trace_id is not null and datepart(weekday, getdate()) not in (6) 
	begin
		exec tracer_log @trace_id, 'просроченные операции, эскалация (не запущен, расписание: пт)'
		return -- nothing todo
	end

	exec tracer_log @trace_id, 'просроченные операции, эскалация (расписание: пт)'

	declare @tasks table (project_id int, task_id int, mol_id int)
	declare @today datetime = dbo.today()

	-- group by project
	insert into @tasks(project_id, task_id, mol_id)
		select t.project_id, t.task_id, 700 /*mols.chief_id*/
			from projects_tasks t
				inner join projects_tasks_raci raci on raci.task_id = t.task_id and charindex('A', raci.raci) >= 1
					inner join mols on mols.mol_id = raci.mol_id
		where t.d_before < @today
			and t.has_childs = 0
			and t.progress < 1
			and t.status_id <> -1

	declare @result table(
		result_id int identity primary key
		, project_id int, mol_id int, content varchar(max))
	
	insert into @result(project_id, mol_id, content) 
	select u.project_id, u.mol_id,
		'Проект "' + projects.name + '"'  + '.' + char(10) + char(13) +
		'Просроченные операции (эскалация):' + char(10)
	from (
		select distinct project_id, mol_id from @tasks
		) u
		inner join projects on projects.project_id = u.project_id

	update r
	set content = content + (
			select '    - ' + title + ' ' + ltrim(title) + ' (просрочено ' + cast(-datediff(d, @today, d_before) as varchar) + ' дн)' + ';' as [text()]
			from (
				select t.project_id, t.task_id, cast(t.task_number as varchar) + '.' + t.name as title, t.d_before
				from @tasks tt
					inner join projects_tasks t on t.task_id = tt.task_id						
				where t.project_id = r.project_id
					and t.status_id <> -1
					and tt.mol_id = r.mol_id
				) m
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', char(10))

	declare @events table(event_id int, result_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		2, -- projects
		10, -- ProjectTaskOverdueEscalateChief
		null, -- priority_id
		1, -- status_id
		'Просроченные операции (эскалация)',
		content,
		result_id
	from @result

	update e
	set href = 'projects/' + cast(r.project_id as varchar) + '/plan?EVENT_ID=' + cast(e.event_id as varchar)
	from events e
		inner join @result r on r.result_id = e.reserved
	where e.event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
		select distinct event_id, mol_id
		from (
			select e.event_id, r.mol_id from @events e
				inner join @result r on r.result_id = e.result_id
			union select event_id, 700 from @events e -- DEBUG
			) u
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'PTS', task_id	
	from (
		select e.event_id, t.task_id 
		from @events e
			join @result r on r.result_id = e.result_id
			join @tasks t on t.project_id = r.project_id and t.mol_id = r.mol_id
		) u
end
go
-- просроченные отчёты по рискам
create proc events_raise;25
	@trace_id int	
as
begin

	-- Вторник
	if @trace_id is not null and datepart(weekday, getdate()) not in (3) 
	begin
		exec tracer_log @trace_id, 'просроченные отчёты по рискам (не запущен, расписание: вторник)'
		return -- nothing todo
	end

	exec tracer_log @trace_id, 'просроченные отчёты по рискам (расписание: вторник)'

	declare @risks table (project_id int, risk_id int, mol_id int)
	declare @yesterday datetime = dbo.today() - 1 -- понедельник

	-- check status_id
	update projects_risks
	set status_id =
			case
				when status_id = 1 and d_last_report < @yesterday then 2 -- Просрочено
				else status_id
			end
	where has_childs = 0
		and is_deleted = 0

	-- group by project
	insert into @risks(project_id, risk_id, mol_id)
		select t.project_id, t.risk_id, raci.mol_id
			from projects_risks t
				inner join projects_risks_raci raci on raci.risk_id = t.risk_id and charindex('R', raci.raci) >= 1
					inner join mols on mols.mol_id = raci.mol_id
		where t.status_id = 2

	declare @result table(
		result_id int identity primary key
		, project_id int, mol_id int, content varchar(max))
	
	insert into @result(project_id, mol_id, content) 
	select u.project_id, u.mol_id,
		'Проект "' + projects.name + '"'  + '. Просроченные отчёты по рискам проекта:' + char(10)
	from (
		select distinct project_id, mol_id from @risks
		) u
		inner join projects on projects.project_id = u.project_id

	update r
	set content = content + (
			select '    - ' + title + ' (просрочено ' + cast(-datediff(d, @yesterday, d_last_report) as varchar) + ' дн)' + ';' as [text()]
			from (
				select t.project_id, t.risk_id, t.name as title, t.d_last_report
				from @risks tt
					inner join projects_risks t on t.risk_id = tt.risk_id						
				where t.project_id = r.project_id
					and tt.mol_id = r.mol_id
				) m
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', char(10))

	declare @events table(event_id int, result_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		2, -- projects
		11, -- ProjectRiskOverdue
		null, -- priority_id
		1, -- status_id
		'Просроченные отчёты по рискам',
		content,
		result_id
	from @result

	update e
	set href = 'projects/' + cast(r.project_id as varchar) + '/risks?EVENT_ID=' + cast(e.event_id as varchar)
	from events e
		inner join @result r on r.result_id = e.reserved
	where e.event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
		select distinct event_id, mol_id
		from (
			select e.event_id, r.mol_id from @events e
				inner join @result r on r.result_id = e.result_id
			) u
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'PTR', risk_id	
	from (
		select e.event_id, t.risk_id 
		from @events e
			join @result r on r.result_id = e.result_id
			join @risks t on t.project_id = r.project_id and t.mol_id = r.mol_id
		) u
end
go
-- задачи этой недели
create proc [dbo].[events_raise];30
	@trace_id int	
as
begin
	
	-- по понедельникам
	if @trace_id is not null and datepart(weekday, getdate()) <> 2
	begin
		exec tracer_log @trace_id, 'задачи этой недели (не запущен, расписание: пн)'
		return -- nothing todo
	end
		
	exec tracer_log @trace_id, 'задачи этой недели (расписание: пн)'

	declare @tasks table (task_id int, d_deadline datetime, author_id int, analyzer_id int, executor_id int, admin_id int)
	declare @week_start datetime; set @week_start = dbo.week_start(dbo.today())
	declare @week_end datetime; set @week_end = @week_start + 6
	declare @cr varchar(2) = char(10)

-- Срок наступает на этой неделе
	-- group by author
	insert into @tasks(task_id, d_deadline, author_id, analyzer_id)
	select task_id, d_deadline, author_id, analyzer_id from tasks where d_deadline between @week_start and @week_end
		and status_id not in (-1,5)

	-- group by executor
	insert into @tasks(task_id, d_deadline, executor_id)
	select distinct task_id, d_deadline, mol_id
	from tasks_mols where task_id in (select task_id from tasks where status_id = 2)
		and d_deadline between @week_start and @week_end
		and d_executed is null

	-- DEBUG: group by admin
	insert into @tasks(task_id, d_deadline, admin_id)
	select task_id, min(d_deadline), 700
	from @tasks
	group by task_id

	declare @result table(mol_id int, content varchar(max))
	
	insert into @result(mol_id, content) 
	select mol_id, 'Задачи со сроком реализации на этой неделе:' + @cr
	from (
		select distinct author_id as mol_id from @tasks where author_id is not null	
		union select distinct analyzer_id from @tasks where analyzer_id is not null	
		union select distinct executor_id from @tasks where executor_id is not null	
		union select distinct admin_id from @tasks where admin_id is not null	
		) u

	update r
	set content = content + (
			select '    - #' + cast(task_id as varchar) + ' ' + ltrim(title) + ' (' + cast(datediff(d, d_deadline, @week_end) as varchar) + ' дн)' + ';' as [text()]
			from (
				select mm.mol_id, t.task_id, t.title, mm.d_deadline
				from (
					select distinct author_id as mol_id, task_id, d_deadline from @tasks where author_id is not null
					union select analyzer_id, task_id, d_deadline from @tasks where analyzer_id is not null
					union select executor_id, task_id, d_deadline from @tasks where executor_id is not null
					union select admin_id, task_id, d_deadline from @tasks where admin_id is not null
					) mm
					inner join tasks t on t.task_id = mm.task_id
				) m
				where m.mol_id = r.mol_id
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', @cr)

	declare @events table(event_id int, mol_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		3, -- tasks
		5, -- TaskThisWeek
		1, -- priority_id
		1, -- status_id
		'Задачи текущей недели',
		content,
		mol_id
	from @result

	update events
	set href = 'tasks?EVENT_ID=' + cast(EVENT_ID as varchar)
	where event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id)
		select event_id, mol_id 
		from @events
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'TSK', task_id	
	from (
		select e.event_id, t.task_id from @events e, @tasks t where t.author_id = e.mol_id
		-- refs by analyzer_id
		union select e.event_id, t.task_id from @events e, @tasks t where t.analyzer_id = e.mol_id
		-- refs by executor_id
		union select e.event_id, t.task_id from @events e, @tasks t where t.executor_id = e.mol_id
		-- refs by admin_id
		union select e.event_id, t.task_id from @events e, @tasks t where t.admin_id = e.mol_id
		) u
end
go
-- просроченные задачи
create proc [dbo].[events_raise];31
	@trace_id int	
as
begin
	
	-- Понедельник, Среда
	if @trace_id is not null and datepart(weekday, getdate()) not in (2,4)
	begin
		exec tracer_log @trace_id, 'просроченные задачи (не запущен, расписание: пн,ср)'
		return -- nothing todo
	end
	
	exec tracer_log @trace_id, 'просроченные задачи (расписание: пн,ср)'

	declare @tasks table (task_id int, d_deadline datetime, author_id int, analyzer_id int, executor_id int, admin_id int)
	declare @today datetime; set @today = dbo.today()
	declare @cr varchar(2) = char(10)

	-- group by author
	insert into @tasks(task_id, d_deadline, author_id)
	select task_id, d_deadline, author_id from tasks where d_deadline < @today
		and status_id in (1,4)
	-- group by analyzer
	insert into @tasks(task_id, d_deadline, analyzer_id)
	select task_id, d_deadline, analyzer_id from tasks where d_deadline < @today
		and status_id in (3)
	-- group by executor
	insert into @tasks(task_id, d_deadline, executor_id)
	select distinct task_id, d_deadline, mol_id
	from tasks_mols where d_deadline < @today
		and task_id in (select task_id from tasks where status_id = 2)
		and d_executed is null
	-- DEBUG: group by admin
	insert into @tasks(task_id, d_deadline, admin_id)
	select task_id, min(d_deadline), 700
	from @tasks
	group by task_id

	declare @result table(mol_id int, content varchar(max))
	
	insert into @result(mol_id, content) 
	select mol_id, 'Просроченные задачи на текущий момент:' + @cr
	from (
		select distinct author_id as mol_id from @tasks where author_id is not null	
		union select distinct analyzer_id from @tasks where analyzer_id is not null	
		union select distinct executor_id from @tasks where executor_id is not null	
		union select distinct admin_id from @tasks where admin_id is not null
		) u

	update r
	set content = content + (
			select '    - #' + cast(task_id as varchar) + ' ' + ltrim(title) + ' (просрочено ' + cast(datediff(d, d_deadline, @today) as varchar) + ' дн)' + ';' as [text()]
			from (
				select mm.mol_id, t.task_id, t.title, mm.d_deadline
				from (
					select distinct author_id as mol_id, task_id, d_deadline from @tasks where author_id is not null
					union select analyzer_id, task_id, d_deadline from @tasks where analyzer_id is not null
					union select executor_id, task_id, d_deadline from @tasks where executor_id is not null
					union select admin_id, task_id, d_deadline from @tasks where admin_id is not null
					) mm
					inner join tasks t on t.task_id = mm.task_id
				) m
				where m.mol_id = r.mol_id
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', @cr)

	declare @events table(event_id int, mol_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		3, -- tasks
		6, -- TaskOverdue
		2, -- priority_id
		1, -- status_id
		'Просроченные задачи',
		content,
		mol_id
	from @result

	update events
	set href = 'tasks?EVENT_ID=' + cast(EVENT_ID as varchar)
	where event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
		select event_id, mol_id 
		from @events
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'TSK', task_id	
	from (
		select e.event_id, t.task_id from @events e, @tasks t where t.author_id = e.mol_id
		-- refs by analyzer_id
		union select e.event_id, t.task_id from @events e, @tasks t where t.analyzer_id = e.mol_id
		-- refs by executor_id
		union select e.event_id, t.task_id from @events e, @tasks t where t.executor_id = e.mol_id
		-- refs by admin_id
		union select e.event_id, t.task_id from @events e, @tasks t where t.admin_id = e.mol_id
		) u
end
go
-- просроченные задачи (эскалация)
create proc [dbo].[events_raise];32
	@trace_id int
as
begin
	
	-- Пятница
	if @trace_id is not null and datepart(weekday, getdate()) not in (6) 
	begin
		exec tracer_log @trace_id, 'просроченные задачи, эскалация (не запущен, расписание: пт)'
		return -- nothing todo
	end

	exec tracer_log @trace_id, 'просроченные задачи, эскалация (расписание: пт)'

	declare @tasks table (task_id int, d_deadline datetime, chief_id int)
	declare @today datetime; set @today = dbo.today()
	declare @cr varchar(2) = char(10)

	-- group by chief of executor
	insert into @tasks(task_id, d_deadline, chief_id)
	select distinct tm.task_id, tm.d_deadline, 700 /* TODO */
	from tasks_mols tm
	where tm.d_deadline < @today
		and tm.task_id in (select task_id from tasks where status_id = 2)
		and tm.d_executed is null

	declare @result table(mol_id int, content varchar(max))
	
	insert into @result(mol_id, content) 
	select mol_id, 'Просроченные задачи на текущий момент (эскалация):' + @cr
	from (
		select distinct chief_id as mol_id from @tasks
		) u

	update r
	set content = content + (
			select '    - #' + cast(task_id as varchar) + ' ' + ltrim(title) + ' (просрочено ' + cast(datediff(d, d_deadline, @today) as varchar) + ' дн)' + ';' as [text()]
			from (
				select mm.mol_id, t.task_id, t.title, mm.d_deadline
				from (
					select distinct chief_id as mol_id, task_id, d_deadline from @tasks
					) mm
					inner join tasks t on t.task_id = mm.task_id
				) m
				where m.mol_id = r.mol_id
			for xml path('')
			)
	from @result r

	update @result set content = replace(content, ';', @cr)

	declare @events table(event_id int, mol_id int)
	-- events
	insert into events(feed_id, feed_type_id, priority_id, status_id, name, content, reserved)
	output inserted.event_id, inserted.reserved into @events
	select 
		3, -- tasks
		7, -- TaskOverdueEscalateChief
		2, -- priority_id
		1, -- status_id
		'Просроченные задачи',
		content,
		mol_id
	from @result

	update events
	set href = 'tasks?EVENT_ID=' + cast(EVENT_ID as varchar)
	where event_id in (select event_id from @events)

	-- mols
	insert into events_mols(event_id, mol_id) 
	select distinct event_id, mol_id
	from @events
	
	-- refs by author_id
	insert into events_objs_refs(event_id, obj_type, obj_id) 
	select distinct event_id, 'TSK', task_id	
	from (
		select e.event_id, t.task_id from @events e, @tasks t where t.chief_id = e.mol_id
		) u
end
go
