if object_id('project_tasks_search') is not null drop proc project_tasks_search
go
create proc project_tasks_search
	@project_id int,
	@mol_id int = null,
	@search varchar(500) = null,
	@priority_id int = null,	
	@d_from datetime = null,
	@d_to datetime = null,
	@extra_id int = null,
		-- 100 Все задачи
		--{ id: 7, name: 'Задачи на неделю' },
		--{ id: 8, name: 'Задачи на две недели' },
		--{ id: 11, name: 'Задачи на месяц' },
		--{ id: 1, name: 'Критический путь' },
		--{ id: 5, name: 'Незавершённые задачи' },
		--{ id: 9, name: 'Просроченые задачи' },
		--{ id: 12, name: 'Завершённые задачи' },
		--{ id: 6, name: 'Непройденные вехи' },
		--{ id: 1000, name: 'Ошибки (пропущенные связи)' }
		--{ id: 1001, name: 'Ошибки (зацикливание)' }
		--{ id: 13, name: 'Открытые связанные задачи' },
		-- 60 Вехи проекта
		-- 70 Задачи на период @d_from, @d_to (включая сделанные)
	@raci_mol_id int = null,
	@raci_mask varchar(16) = null,
	@event_id int = null,
	@root_id int = null,
	@parent_id int = null
as
begin

	set nocount on;
	
	declare @root hierarchyid; select @root = node from projects_tasks where task_id = @root_id	
    declare @task_id int

	create table #childs(task_id int index ix_task)
	create table #result(task_id int primary key)

	if @parent_id is not null
	begin
		insert into #result
		select task_id from projects_tasks
		where project_id = @project_id
			and parent_id = @parent_id
	end	
	
	else if @search is null 
		and @priority_id is null 
		and @extra_id is null
		and @raci_mol_id is null
	begin
		insert into #childs
		select task_id from projects_tasks where project_id = @project_id
			and (
				(@root_id is null and parent_id is null) or task_id = @root_id
				)
	end	

	else if left(@search, 1) in ('<', '>', '*')
	-- найти всех предшественников
	begin
		declare @mode char(1) = substring(@search, 1, 1)

		set @search = substring(@search, 2, 32)
				
		if isnumeric(@search) = 1
		begin
			select @task_id = task_id from projects_tasks where project_id = @project_id and task_number = cast(@search as int)

			if @mode = '<'
				insert into #childs(task_id)
				select l.source_id
				from projects_tasks_links l
					inner join projects_tasks t on t.task_id = l.source_id
				where l.target_id = @task_id
			
			-- найти всех наследников
			else if @mode = '>'
				insert into #childs(task_id)
				select l.target_id
				from projects_tasks_links l
					inner join projects_tasks t on t.task_id = l.target_id
				where l.source_id = @task_id

			-- найти всех предшественников и наследников
			else if @mode = '*'
				insert into #childs(task_id)
				select l.task_id
				from (
					select target_id as task_id from projects_tasks_links where source_id = @task_id
					union
					select source_id from projects_tasks_links where target_id = @task_id
					) l
					inner join projects_tasks t on t.task_id = l.task_id
		end
	end

	else begin
	
		if @search is not null
			and not exists(
				select 1
				from dbo.str2rows(@search,',')
				where try_parse(item as int) is null
				)
		begin
			insert into #childs(task_id)
			select task_id
			from projects_tasks
			where project_id = @project_id
				and task_number in (select item from dbo.str2rows(@search, ','))
		end

		else begin

            if dbo.hashid(@search) is not null
            begin
		    	set @task_id = dbo.hashid(@search)
                set @search = null
            end

			declare @today datetime; set @today = dbo.today()
			declare @week_end datetime; set @week_end = dateadd(d, 6, dbo.week_start(@today))
			declare @next_end datetime; set @next_end = dateadd(d, 6, dbo.week_start(dateadd(d, 7, @today)))
			declare @month_start datetime; set @month_start = dateadd(d, -datepart(day, @today) + 1, @today)
			declare @month_end datetime; set @month_end = dateadd(m, 1, @month_start) - 1

			set @search = '%' + @search + '%'

			declare @ids_extra as app_pkids
			if @extra_id = 1001
			begin
				insert into @ids_extra
					select next_task_id
					from (
						select 
							task_id, 
							execute_level,
							next_level = lead(execute_level, 1, null) over (partition by project_id order by execute_level, task_number),
							next_task_id = lead(task_id, 1, null) over (partition by project_id order by execute_level, task_number)
						from projects_tasks x
						where project_id = @project_id
							and execute_level > 0
						) u
					where (u.next_level - u.execute_level) > 2
			end

			-- search
			insert into #childs(task_id)
			select distinct task_id
			from projects_tasks pp
			where project_id = @project_id
                and (@task_id is null or task_id = @task_id)
				and (is_deleted = 0)
				and (@search is null 
					or pp.name + isnull(pp.tags,'') + isnull(pp.description,'') like @search
					)
				and (@priority_id is null or pp.priority_id = @priority_id)			
				and (
					@extra_id is null
					or (@extra_id = 100)
					-- { id: 1, name: 'Критический путь' },
					or (@extra_id = 1 and ((pp.is_critical = 1 and isnull(pp.progress,0) < 1.0) or pp.is_long = 1))
					-- { id: 4, name: 'Отставание по сроку' },
					or (@extra_id = 4 and pp.d_to > pp.d_before and pp.progress < 1.0)
					-- { id: 5, name: 'Незавершённые задачи' },
					or (@extra_id = 5 and isnull(pp.progress,0) < 1.0)
					-- { id: 12, name: 'Завершённые задачи' },
					or (@extra_id = 12 and pp.progress = 1.0)
					-- { id: 6, name: 'Непройденные вехи' },
					or (@extra_id = 6 and pp.duration = 0 and pp.progress < 1.0)
					or (@extra_id = 60 and pp.duration = 0)
					-- { id: 7, name: 'Задачи на неделю' }
					or (@extra_id = 7 and (pp.d_from <= @week_end and progress < 1 and has_childs = 0))
					-- 70 Задачи на период @d_from, @d_to (включая сделанные)
					or (@extra_id = 70 and (pp.d_from <= @d_to and progress < 1 and has_childs = 0))
					-- { id: 8, name: 'Задачи на две недели' },
					or (@extra_id = 8 and (pp.d_from <= @next_end and progress < 1 and has_childs = 0))
					-- { id: 9, name: 'Просроченые задачи' },
					or (@extra_id = 9 and (pp.d_before <= @today and progress < 1 and has_childs = 0))
					-- { id: 11, name: 'Задачи на месяц' },
					or (@extra_id = 11 and (pp.d_from <= @month_end and progress < 1 and has_childs = 0))
					-- { id: 1000, name: 'Ошибки (пропущенные связи)' }
					or (@extra_id = 1000 and pp.task_id in (
							select task_id from projects_tasks tt
							where project_id = @project_id 
								and has_childs = 0
								and progress < 1
								and is_critical = 0
								and not exists(select 1 from projects_tasks_links where target_id = tt.task_id)
						))
					-- { id: 1001, name: 'Ошибки (зацикливание)' }
					or (@extra_id = 1001 
						and pp.task_id in (select id from @ids_extra)
						)
					-- { id: 13, name: 'Открытые связанные задачи' },
					or (@extra_id = 13 and exists(
							select 1 from tasks
							where project_task_id = pp.task_id
								and (status_id between 1 and 4)
						))
					)
				and (
					@raci_mol_id is null or
						exists(select 1 from projects_tasks_raci where task_id = pp.task_id and mol_id = @raci_mol_id and charindex(@raci_mask,raci) >= 1)
					)
				and (
					@event_id is null
					or exists(select 1 from events_objs_refs where event_id = @event_id and obj_type = 'PTS' and obj_id = pp.task_id)
					)
		end
	end

-- get all parents
	if @parent_id is null
	begin
		;with tree as (
			select parent_id, task_id from projects_tasks where task_id in (select task_id from #childs)
			union all
			select t.parent_id, t.task_id
			from projects_tasks t
				inner join tree on tree.parent_id = t.task_id
			where t.project_id = @project_id
			)
			insert into #result(task_id) select distinct task_id from tree
	end

-- return results	
	select t.task_id from projects_tasks t
		join #result r on r.task_id = t.task_id
	where (@root is null or node.IsDescendantOf(@root) = 1)
		and is_deleted = 0

	exec drop_temp_table '#childs,#result'
end
go
