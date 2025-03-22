if object_id('dhx_gantt_tasks_view') is not null
	drop proc dhx_gantt_tasks_view
go
/*
** IMPORTANT: output used as insert into ... exec dhx_gantt_tasks_view
** Any changes here must be agreed with correspondent procedures
*/
-- exec dhx_gantt_tasks_view 1
create proc dhx_gantt_tasks_view
	@project_id int,
	@search varchar(max) = null,
	@show_done bit = 1,
	@layer varchar(32) = 'plan', -- values: plan, duty
	@root_id int = null
as
begin

	set nocount on;

	declare @extra_id int = case when @show_done = 0 then 5 else 12 end

	create table #tasks (
		task_id int primary key,
		task_number int,
		name varchar(500), 
		d_from datetime,
		d_to datetime,
		duration float,		
		progress float,
		parent_id int,
		outline_level int,
		has_childs bit,
		sort_id float,
		node hierarchyid
		)
		create index ix_tasks_temp on #tasks(node);

-- @layer
	if isnull(@layer,'plan') = 'plan'
		insert into #tasks (
			task_id, task_number, name,
			d_from, d_to, duration, progress,
			node, parent_id, outline_level, has_childs, sort_id
			)
		select 
			task_id, task_number, name,
			d_from, d_to, duration, progress,
			node, parent_id, outline_level, has_childs, sort_id
		from projects_tasks where project_id = @project_id
			and is_deleted = 0

	else if @layer = 'duty'
		insert into #tasks (
			task_id, name,
			d_from, d_to, duration, progress,
			node, parent_id, outline_level, has_childs, sort_id
			)
		select 
			task_id, name,
			d_from, d_to, duration, progress,
			node, parent_id, level_id, has_childs, sort_id
		from projects_duties where project_id = @project_id	
			and is_deleted = 0

-- @search
	if @search is not null or @root_id is not null
	begin		
		declare @result table(task_id int)

		if substring(@search, 1, 2) in ('<<', '>>')
		-- Специальный случай - цепочка задачи
		begin
			declare @mode char(2); set @mode = substring(@search, 1, 2)
			set @search = substring(@search, 3, 32)

			if isnumeric(@search) = 1 begin
				declare @task_id int
				select @task_id = task_id from #tasks where task_number = cast(@search as int)
				-- chain				
				if @mode = '<<'
					insert into @result
					exec project_task_chain @project_id = @project_id, @task_id = @task_id, @predecessors = 1
				else if @mode = '>>'
					insert into @result
					exec project_task_chain @project_id = @project_id, @task_id = @task_id, @predecessors = 0
			end
		end
		
		else begin
			insert into @result
			exec project_tasks_search @project_id = @project_id, @search = @search, @extra_id = @extra_id, @root_id = @root_id
		end
		
		delete from #tasks where task_id not in (select task_id from @result)
	end
	
-- calc summary
	update x
	set d_from = r.d_from,
		d_to = r.d_to
	from #tasks x
		inner join (
			select y2.task_id, 
				min(y1.d_from) as d_from,
				max(y1.d_to) as d_to
			from #tasks y1
				join #tasks y2 on y1.node.IsDescendantOf(y2.node) = 1 and y1.has_childs = 0
			where y2.has_childs = 1
			group by y2.task_id
		) r on r.task_id = x.task_id	

-- final select
	declare @today datetime; set @today = dbo.today()

	select
		t.project_id,
		t.task_id as 'id',
		p.task_number,
		p.name as 'text',
		
		isnull(t.predecessors, '') as 'predecessors',
		coalesce(p.d_from, t.d_from, @today) as 'start_date',
		coalesce(p.d_to, t.d_to, @today + 1) as 'end_date',
		
		--case 
		--	when t.has_childs = 0 and t.base_d_from <> p.d_from then t.base_d_from
		--end as 'base_start',
		null as 'base_start',
				
		--case 
		--	when t.has_childs = 0 and t.base_d_to <> p.d_to then t.base_d_to
		--end as 'base_end',
		null as 'base_end',

		t.duration,
		t.duration_buffer,
		p.progress,
		t.sort_id as 'sortorder',
		case when t.task_id <> isnull(@root_id,0) then t.parent_id end as 'parent',
		case when t.duration = 0 then 'milestone' else 'task' end as 'type',
		t.has_childs as 'open',
		t.is_critical,
		case 
			when t.has_childs = 0 and t.is_critical = 1 then 'К' 
			when t.has_childs = 0 and isnull(t.is_long,0) = 1 then concat('Б', t.duration_buffer)
			else ''
		end as 'is_critical_label',
		t.is_long,
		t.outline_level,
		t.execute_level
	from projects_tasks t
		inner join #tasks p on p.task_id = t.task_id
	order by t.task_number, t.sort_id

	drop table #tasks;
end
go
