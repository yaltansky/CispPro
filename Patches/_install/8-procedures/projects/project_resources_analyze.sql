if object_id('project_resources_analyze') is not null drop proc project_resources_analyze
go

create proc project_resources_analyze
	@mol_id int,
	@tree_id int = null,
	@recalc bit = 0
as
begin

	set nocount on;

-- calc result into cache
	if @recalc = 1
	begin
		-- очистить лог
		delete projects_resources_az_tracking where mol_id = @mol_id and tree_id = @tree_id;
		-- проекты
		exec project_tasks_calc @tree_id = @tree_id, @mol_id = @mol_id
		-- ресурсы
		exec project_tasks_calc_resources @tree_id = @tree_id;
		-- лимиты
		exec project_resources_calc_limits @mol_id = @mol_id, @tree_id = @tree_id;
		-- оборотка
		exec project_resources_analyze;100 @mol_id = @mol_id, @tree_id = @tree_id;			
	end
	
-- #projects_plans
	select 
		fd.resource_id
		, fd.output_q
		, lim.overlimit_q
		, lim.overlimit_date
		, 0 as level
	into #projects_plans
	from (
		select
			fdd.resource_id
			, case when a.aggregation_id = 1 then sum(fdd.output_q) else max(fdd.output_q) end as 'output_q'
		from (
			select 
				r.resource_id, d.d_doc, sum(d.output_q) as output_q
			from projects_resources_az_tasks_days d
				inner join projects_resources_az_tasks r on r.row_id = d.row_id
			where d.tree_id = @tree_id
				and d.has_childs = 0
			group by r.resource_id, d.d_doc
			) fdd
			inner join projects_resources a on a.resource_id = fdd.resource_id
		group by
			fdd.resource_id, a.aggregation_id
		) fd		
		left join (
			select l.resource_id
				, case when a.aggregation_id = 1 then sum(l.overlimit_q) else max(l.overlimit_q) end as 'overlimit_q'
				, min(d_doc) as overlimit_date
			from projects_resources_az_limits l
				inner join projects_resources a on a.resource_id = l.resource_id
			where l.tree_id = @tree_id
				and l.d_doc >= dbo.today()
				and l.overlimit_q > 0
			group by l.resource_id, a.aggregation_id
		) lim on lim.resource_id = fd.resource_id

-- Построить дерево ресурсов
	exec project_resources_analyze;3

-- Конечная выборка
	select
		A.RESOURCE_ID,
		A.NAME,
		A.LEVEL_ID,
		A.HAS_CHILDS,
		B.OUTPUT_Q,
		B.OVERLIMIT_Q,
		B.OVERLIMIT_DATE
	from #projects_plans b
		inner join projects_resources a on a.resource_id = b.resource_id
	where b.resource_id > 0
	order by a.sort_id, a.name
end
GO

create proc project_resources_analyze;3
as
begin

	declare @i int; set @i = 0

	while @i < 30 -- страховка: не более 10 итераций!
	begin		
		-- calc level up
		insert into #projects_plans(resource_id, level)
		select a.parent_id, @i + 1
		from #projects_plans b
			inner join projects_resources a on a.resource_id = b.resource_id
		where b.level = @i
			and a.parent_id is not null
		group by a.parent_id

		if @@rowcount = 0 break -- это значит добрались до верхнего уровня иерархии
		set @i = @i + 1
	end
end
go

create proc project_resources_analyze;100
	@mol_id int,	
	@tree_id int = null,
	@resource_id int = null,
	@d_from datetime = null,
	@d_to datetime = null
as
begin

	set nocount on;

-- @projects
	declare @projects table(project_id int)
	declare @node hierarchyid; select @node = node from trees where tree_id = @tree_id
	insert into @projects select obj_id from trees where node.IsDescendantOf(@node) = 1 and obj_type = 'PRJ' and obj_id is not null

-- clear cache
	if @d_from is null delete from projects_resources_az_tasks where tree_id = @tree_id and (@resource_id is null or resource_id = @resource_id) 
	delete from projects_resources_az_tasks_days where tree_id = @tree_id and (@resource_id is null or resource_id = @resource_id)
		and (@d_from is null or d_doc >= @d_from)
		and (@d_to is null or d_doc <= @d_to)
	
-- #details
	select 
		@tree_id as tree_id, fd.task_id, fd.resource_id, fd.d_doc, fd.quantity
		, cast(null as decimal(18,3)) as limit_q
		, cast(null as decimal(18,3)) as overlimit_q
		, cast(null as datetime) as overlimit_date
		, cast(0 as bit) as has_childs
		, cast(0 as int) as level
	into #details
	from projects_resources_charts fd
		inner join projects_resources a on a.resource_id = fd.resource_id
	where fd.project_id in (select project_id from @projects)
		and (@resource_id is null or fd.resource_id = @resource_id)
		and (@d_from is null or fd.d_doc >= @d_from)
		and (@d_to is null or fd.d_doc <= @d_to)

	update x
	set limit_q = lim.limit_q,
		overlimit_q = lim.overlimit_q,
		overlimit_date = case when lim.overlimit_q > 0 then x.d_doc end
	from #details x
		inner join projects_resources_az_limits lim on lim.tree_id = x.tree_id and lim.resource_id = x.resource_id and lim.d_doc = x.d_doc

	if @d_from is null
	begin
		-- calc parents of tasks
		declare @i int; set @i = 0

		while @i < 30 -- страховка: не более 10 итераций!
		begin		
			-- calc level up
			insert into #details(tree_id, resource_id, task_id, d_doc, quantity, has_childs, level)
			select b.tree_id, b.resource_id, t.parent_id, b.d_doc, sum(quantity), 1, @i + 1
			from #details b
				inner join projects_tasks t on t.task_id = b.task_id			
			where b.level = @i
				and t.parent_id is not null
				and t.is_deleted = 0
			group by b.tree_id, b.resource_id, t.parent_id, b.d_doc

			if @@rowcount = 0 break -- добрались до верхнего уровня иерархии
			set @i = @i + 1
		end

		-- projects_resources_az_tasks
		insert into projects_resources_az_tasks(
			tree_id, task_id, resource_id, output_q, rebate_shift)
		select 
			fd.tree_id, fd.task_id, fd.resource_id
			, case when a.aggregation_id = 1 then sum(fd.quantity) else max(fd.quantity) end
			, track.rebate_shift
		from #details fd
			inner join projects_resources a on a.resource_id = fd.resource_id
			left join projects_resources_az_tracking track on track.mol_id = @mol_id and track.task_id = fd.task_id
		group by fd.tree_id, fd.task_id, fd.resource_id, a.aggregation_id, track.rebate_shift
	end

-- project_resources_analyze_details
	insert into projects_resources_az_tasks_days(
		tree_id, row_id, resource_id, d_doc, output_q, overlimit_q, has_childs)
	select 
		fd.tree_id, r.row_id, fd.resource_id, fd.d_doc, fd.quantity, fd.overlimit_q, fd.has_childs
	from #details fd
		inner join projects_resources_az_tasks r on r.tree_id = fd.tree_id and r.task_id = fd.task_id and r.resource_id = fd.resource_id
end
go
