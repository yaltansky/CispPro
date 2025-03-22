if object_id('project_resources_align') is not null drop proc project_resources_align
go
create proc project_resources_align
	@mol_id int,
	@tree_id int,
	@resource_id int,
	@d_doc datetime = null,
	@d_next datetime = null
as
begin

	set nocount on;

-- check
	declare @overlimit_q decimal(18,3)
	select @overlimit_q = overlimit_q from projects_resources_az_limits 
		where tree_id = @tree_id
			and resource_id = @resource_id 
			and d_doc = @d_doc

	if isnull(@overlimit_q,0) = 0 return -- nothing TODO

-- save tracking
	if not exists(select 1 from projects_resources_az_tracking where mol_id = @mol_id and tree_id = @tree_id)
	begin
		insert into projects_resources_az_tracking(mol_id, tree_id, task_id, d_from, d_after)
		select @mol_id, r.tree_id, r.task_id, t.d_from, t.d_after
		from projects_resources_az_tasks r
			inner join projects_tasks t on t.task_id = r.task_id
		where r.tree_id = @tree_id
			and r.resource_id = @resource_id
	end

-- get rows
	create table #rows (row_id int, task_id int, resource_id int, priority_id int, progress decimal, output_q decimal(18,3), output_sum decimal(18,3))

	insert into #rows(row_id, task_id, progress, resource_id, priority_id, output_q, output_sum)
	select row_id, task_id, progress, resource_id, priority_id, output_q, output_sum
	from (
		select row_id, task_id, progress, resource_id, priority_id, output_q,
			sum(output_q) over(order by priority_id) as output_sum
		from (
			select r.row_id, r.task_id, r.resource_id
				, t.progress
				, case when a.aggregation_id = 1 then sum(d.output_q) else max(d.output_q) end as output_q
				, row_number() over(order by t.project_id, t.duration_buffer desc, t.duration) as priority_id
			from projects_resources_az_tasks r
				inner join projects_resources_az_tasks_days d on d.row_id = r.row_id
				inner join projects_tasks t on t.task_id = r.task_id
				inner join projects_resources a on a.resource_id = r.resource_id
			where r.tree_id = @tree_id
				and r.resource_id = @resource_id
				and d.d_doc = @d_doc
				and t.has_childs = 0 -- только дочерние задачи
				and t.progress = 0 -- только не начатые задачи
				and t.is_critical = 0 -- только не критические задачи
			group by r.row_id, t.project_id, r.task_id, t.progress, t.duration_buffer, t.duration, r.resource_id, a.aggregation_id
			) r
		) rr
	where output_sum < @overlimit_q
	
-- align
	declare @new_d_from datetime; set @new_d_from = dbo.work_day_add(@d_doc, 1)

	declare @tasks table(row_id int, task_id int, output_sum decimal(18,3))	
	insert into @tasks select row_id, task_id, output_sum from #rows
	
	declare @output_sum decimal(18,3)
	set @output_sum = isnull((select max(output_sum) from @tasks), 0)	
	
	if @output_sum < @overlimit_q
	begin
		insert into @tasks
		select top 1 row_id, task_id, output_sum
		from #rows
		where output_sum > @output_sum
		order by output_sum
	end

	-- set new d_after
	exec sys_set_triggers 0
		update t set d_after = @new_d_from from projects_tasks t
			inner join @tasks tt on tt.task_id = t.task_id
	exec sys_set_triggers 1

	-- track rebate_shift
	update track
	set rebate_shift = dbo.work_day_diff(isnull(track.d_after, track.d_from), t.d_after)
	from projects_resources_az_tracking track
		inner join projects_tasks t on t.task_id = track.task_id
			inner join @tasks tt on tt.task_id = t.task_id
	where track.mol_id = @mol_id and track.tree_id = @tree_id
	
	if @d_next is null set @d_doc = null

	-- calc gantt
	exec project_tasks_calc @mol_id = @mol_id, @tree_id = @tree_id, @gantt_only = 1
	-- calc resource (hot)
	exec project_tasks_calc_resources @tree_id = @tree_id, @resource_id = @resource_id, @d_from = @d_doc, @d_to = @d_next
	-- calc resource analyzer
	exec project_resources_analyze;100 @mol_id = @mol_id, @tree_id = @tree_id, @resource_id = @resource_id, @d_from = @d_doc, @d_to = @d_next
	-- calc overlimits
	exec project_resources_calc_limits @mol_id = @mol_id, @tree_id = @tree_id, @resource_id = @resource_id, @d_from = @d_doc, @d_to = @d_next

end
go
