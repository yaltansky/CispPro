if object_id('project_resources_analyze_rows') is not null drop proc project_resources_analyze_rows
go

create proc project_resources_analyze_rows
	@tree_id int,
	@resource_id int,
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,	
	@search varchar(max) = null,
	@extra_id int = null -- 1 - показать изменения
as
begin

	set nocount on;

	if @extra_id = 1 begin
		set @d_doc_from = null
		set @d_doc_to = null
	end

-- get rows
	declare @rows table(row_id int, task_id int, resource_id int, output_q decimal(18,3), count_days int)
	insert into @rows(row_id, task_id, resource_id, output_q, count_days)
	select r.row_id, r.task_id, r.resource_id
		, case when a.aggregation_id = 1 then sum(d.output_q) else max(d.output_q) end as output_q		
		, count(*)
	from projects_resources_az_tasks r
		inner join projects_resources_az_tasks_days d on d.row_id = r.row_id
		inner join projects_tasks t on t.task_id = r.task_id
		inner join projects_resources a on a.resource_id = r.resource_id
	where r.tree_id = @tree_id
		and r.resource_id = @resource_id
		and t.has_childs = 0
		and (@d_doc_from is null or d.d_doc >= @d_doc_from)
		and (@d_doc_to is null or d.d_doc <= @d_doc_to)
		and (@extra_id is null 
			or (@extra_id = 1 and (r.rebate_shift > 0))
			)
	group by r.row_id, r.task_id, r.resource_id, a.aggregation_id

-- build tasks tree
	declare @tasks table (
		xtask_id int identity primary key,
		xparent_id int,
		row_id int,
		project_id int,
		resource_id int,
		task_id int,
		d_from_old datetime,
		duration decimal(18,2),
		output_q decimal(18,3),
		count_days int,
		has_childs bit,
		level_id int
		)

	-- ... by terms
	insert into @tasks(row_id, project_id, resource_id, task_id, d_from_old, duration, output_q, count_days, has_childs, level_id)
	select r.row_id, t.project_id, r.resource_id, r.task_id, coalesce(track.d_after, track.d_from, t.d_from), t.duration, r.output_q, r.count_days, 0, t.outline_level
	from @rows r
		inner join projects_tasks t on t.task_id = r.task_id
		inner join projects_tasks_resources tr on tr.task_id = t.task_id and tr.resource_id = @resource_id
		left join projects_resources_az_tracking track on track.tree_id = @tree_id and track.task_id = t.task_id
	where t.has_childs = 0
		and (@search is null or t.name like '%' + @search + '%')
	
	declare @level int; set @level = (select max(level_id) from @tasks)

	-- ... by parents
	while @level > 0
	begin
		insert into @tasks(project_id, task_id, resource_id, duration, output_q, count_days, has_childs, level_id)
		select t.project_id, t.parent_id, tt.resource_id, sum(tt.duration), sum(tt.output_q), sum(tt.count_days), 1, @level - 1
		from @tasks tt
			inner join projects_tasks t on t.task_id = tt.task_id
		where tt.level_id = @level
			and t.parent_id is not null
		group by t.project_id, t.parent_id, tt.resource_id

		set @level = @level - 1
	end

	update x
	set xparent_id = y.xtask_id
	from @tasks x
		inner join projects_tasks t on t.task_id = x.task_id
			inner join @tasks y on y.task_id = t.parent_id

	-- ... by projects
	insert into @tasks(project_id, task_id, resource_id, duration, output_q, count_days, has_childs, level_id)
	select
		p.project_id
		, -p.project_id
		, r.resource_id
		, sum(r.duration)
		, sum(r.output_q)
		, sum(r.count_days)
		, 1
		, 0
	from @tasks r
		inner join projects p on p.project_id = r.project_id
	where r.level_id = 1
	group by p.project_id, r.resource_id

	update x
	set xparent_id = y.xtask_id
	from @tasks x
		inner join @tasks y on y.project_id = x.project_id and y.level_id = 0
	where x.level_id = 1
	
	-- final select
	select
		R.XTASK_ID,
		R.XPARENT_ID,
		R.ROW_ID,
		R.RESOURCE_ID,
		TREE_ID = @tree_id,
		p.PROJECT_ID,
		T.TASK_ID,
		NAME = isnull(T.NAME, P.NAME),
		TASK_NUMBER = isnull(T.TASK_NUMBER, 0),
		R.D_FROM_OLD,
		T.D_FROM, T.D_TO, T.D_AFTER,
		T.DURATION_BUFFER, T.PROGRESS,
		T.IS_CRITICAL, T.IS_LONG, T.IS_OVERLONG, T.EXECUTE_LEVEL,
		R.HAS_CHILDS,
		OUTLINE_LEVEL = R.LEVEL_ID,
		R.OUTPUT_Q,
		QUANTITY = R.OUTPUT_Q,
		DURATION = cast(R.COUNT_DAYS as float),
		RW.REBATE_SHIFT
	from @tasks r
		inner join projects p on p.project_id = r.project_id
		left join projects_resources_az_tasks rw on rw.row_id = r.row_id
		left join projects_tasks t on t.task_id = r.task_id
	order by 
		p.name,
		t.sort_id

end
go
