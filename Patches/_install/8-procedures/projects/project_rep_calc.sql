if object_id('project_rep_calc') is not null drop proc project_rep_calc
go
create proc project_rep_calc
	@report_id int
as
begin

	set nocount on;

	-- calculte project
	declare @project_id int, @mol_id int, @rep_type_id int, @status_id int, @rep_d_from datetime, @rep_d_to datetime
	select 
		@project_id = project_id,
		@mol_id = mol_id,
		@rep_type_id = rep_type_id,
		@status_id = status_id,
		@rep_d_from = d_from,
		@rep_d_to = d_to
	from projects_reps where rep_id = @report_id
	
	declare @today datetime; set @today = dbo.today()

	if @status_id = 10
	begin
		raiserror('Оперативный отчёт находится в состоянии Архив. Изменение невозможно.', 16, 1)
		return
	end

	declare @tree_id int = (select tree_id from trees where obj_type = 'PRJ' and obj_id = @project_id)

	print 'пересчёт проекта'
	exec project_tasks_calc @project_id = @project_id

	print 'пересчёт графика ресурсов'
	exec project_tasks_calc_resources @tree_id = @tree_id;

	print 'пересчёт оборотки'
	exec project_resources_analyze;100 @mol_id = @mol_id, @tree_id = @tree_id;			
	
	print 'actualize reports tasks'
	declare 
		@d_from_old datetime, @d_to_old datetime
		, @d_from datetime, @d_to datetime, @progress_current decimal(18,2)		

	update projects_reps_tasks set is_current = 0 where rep_id = @report_id
	
	update rep
	set is_current = 0, has_childs = t.has_childs, parent_id = t.parent_id, node = t.node,
		duration_buffer = t.duration_buffer,
		is_critical = t.is_critical,
		is_long = t.is_long,
		execute_level = t.execute_level
	from projects_reps_tasks rep
		inner join projects_tasks t on t.task_id = rep.task_id
	where rep.rep_id = @report_id

	update rep
	set @d_from = isnull(t.d_from_fact, t.d_from),
		@d_to = isnull(t.d_to_fact, t.d_to),
		@d_from_old = rep.old_d_from,
		@d_to_old = rep.old_d_to,
		
		-- исходящий %
		@progress_current = isnull(
			case
				when @today < @rep_d_to then t.progress
				when @d_from >= @rep_d_to then rep.progress
				when @d_to <= @rep_d_to then 1
				else dbo.work_day_diff(@d_from, @rep_d_to) / nullif(t.duration,0)
			end,
			0),

		progress_current = 
			case
				when @progress_current > 1 then 1
				else @progress_current
			end,
		
		-- задача отчётного периода?
		is_current = 
			case
				when (@d_from between @rep_d_from and @rep_d_to)
					or (@d_to between @rep_d_from and @rep_d_to)
					then 1
				when (@d_from_old > @rep_d_to or @d_to_old < @rep_d_from) 
					then 0
				else 1
			end,

		d_to_current = @d_to,
		d_to_diff = dbo.work_day_diff(rep.old_d_to, t.d_to),

		d_from = @d_from,
		d_to = @d_to,
		d_from_fact = t.d_from_fact,
		d_to_fact = t.d_to_fact,
				
		count_checks = t.count_checks,
		count_checks_all = t.count_checks_all,
		task_number = t.task_number
	from projects_reps_tasks rep
		inner join projects_tasks t on t.task_id = rep.task_id
	where rep.rep_id = @report_id
		and t.has_childs = 0

-- calc totals
	create table #plan (
		task_id int primary key, parent_id int, has_childs bit, outline_level int,
		d_from datetime, d_to datetime,
		duration int, progress decimal(18,2), count_checks int, count_checks_all int,
		is_current bit
		)

	insert into #plan(task_id, parent_id, has_childs, outline_level, d_from, d_to, progress, duration, is_current)
		select task_id, parent_id, has_childs, outline_level, d_from, d_to, progress_current, duration, is_current
		from projects_reps_tasks
		where rep_id = @report_id

	print 'project_tasks_calc_totals'
	exec project_tasks_calc_totals @project_id = @project_id

	update rt
	set d_from = p.d_from,
		d_to = p.d_to,
		progress_current = p.progress,
		duration = p.duration
	from projects_reps_tasks rt
		inner join #plan p on p.task_id = rt.task_id
	where rep_id = @report_id
		and p.has_childs = 1		
	
	update x
	set is_current = 
			case
				when exists(
					select 1 from projects_reps_tasks 
					where rep_id = @report_id and node.IsDescendantOf(x.node) = 1 and has_childs = 0 and is_current = 1
					) then 1
				else 0
			end
	from projects_reps_tasks x
	where x.rep_id = @report_id
		and x.has_childs = 1

-- calc resources
	declare @deleted table(resource_id int, task_id int, q_output decimal(18,2))

	delete from projects_reps_resources 
		output deleted.resource_id, deleted.task_id, deleted.q_output into @deleted
	where rep_id = @report_id

	declare @current_date datetime = case when @today < @rep_d_to then @today else @rep_d_to end

	insert into projects_reps_resources(rep_id, resource_id, task_id, q_input, q_current, q_output, q_end)
	select 
		@report_id,
		u.resource_id,
		u.task_id,
		u.q_input,
		u.q_current_calc,
		r.quantity *
			case
				when rt2.date_diff = 0 then 0
				when rt.old_d_from <= rep.d_to and rt.old_d_to > rep.d_to 
					then 1.0 * dbo.work_day_diff_core(rt.old_d_from, rep.d_to) / nullif(rt2.date_diff,0)
				else 1
			end,
		r.quantity
	from (
		select 		
			zd.resource_id,
			zt.task_id,
			sum(case when d_doc < @rep_d_from then zd.output_q end) as q_input,
			sum(case when d_doc <= @current_date then zd.output_q end) as q_current_calc
		from projects_resources_az_tasks_days zd
			inner join projects_resources_az_tasks zt on zt.row_id = zd.row_id
		where zt.tree_id = @tree_id	
			and zd.has_childs = 0
		group by zd.resource_id, zt.task_id
		) u
		inner join projects_reps_tasks rt on rt.rep_id = @report_id and rt.task_id = u.task_id and rt.is_current = 1
			inner join (
				select 
					x.rep_id,
					x.task_id,
					dbo.work_day_diff_core(x.old_d_from, x.old_d_to) as date_diff
				from projects_reps_tasks x
			) rt2 on rt2.rep_id = rt.rep_id and rt2.task_id = rt.task_id
			inner join projects_reps rep on rep.rep_id = rt.rep_id
		inner join projects_tasks_resources r on r.resource_id = u.resource_id and r.task_id = u.task_id
		left join @deleted d on d.resource_id = u.resource_id and d.task_id = u.task_id

	print 'calc budgets'
	exec project_rep_calc;10 @report_id = @report_id

	update projects_reps
	set d_calc = @today
	where rep_id = @report_id

end
go
-- calc budgets
create proc project_rep_calc;10
	@report_id int
as
begin

	set nocount on;
	
	declare @project_id int, @rep_d_from datetime, @rep_d_to datetime
	select 
		@project_id = project_id,
		@rep_d_from = d_from,
		@rep_d_to = d_to
	from projects_reps where rep_id = @report_id

-- @budget_id
	if (select count(*) budget_id from budgets where project_id = @project_id and is_deleted = 0) > 1
		return -- budget must be one

	declare @budget_id int = (select budget_id from budgets where project_id = @project_id and is_deleted = 0)

-- @plan
	declare @plan table(
		row_id int identity primary key,
		article_id int,
		inout int,
		value decimal(18,2)
		)

	insert into @plan(article_id, inout, value)
	select article_id, inout, sum(plan_bds)
	from projects_reps_budgets
	where rep_id = @report_id
	group by article_id, inout
	having sum(abs(plan_bds)) >= 0.01

-- @findocs
	declare @findocs table(
		subject_id int,
		agent_id int,
		article_id int,
		findoc_id int, d_doc datetime, fact_dds decimal(18,2), internal bit default(0)
		)

	insert into @findocs(subject_id, agent_id, article_id, findoc_id, d_doc, fact_dds)
		select fd.subject_id, fd.agent_id, fd.article_id, fd.findoc_id, fd.d_doc, sum(fd.value_ccy) as value_ccy
		from (
			select
				f.subject_id,
				f.agent_id,
				f.d_doc,
				f.findoc_id,
				isnull(fdd.budget_id, f.budget_id) as 'budget_id',
				coalesce(fdd.article_id, f.article_id, 0) as 'article_id',
				isnull(fdd.value_ccy, f.value_ccy) as 'value_ccy'
			from findocs f
				left join findocs_details fdd on fdd.findoc_id = f.findoc_id				
			) fd		
			inner join bdr_articles a on a.article_id = fd.article_id
		where fd.budget_id = @budget_id
		group by fd.subject_id, fd.agent_id, fd.article_id, fd.d_doc, fd.findoc_id

		-- internal
		update x
		set internal = 1
		from @findocs x
			inner join subjects s on s.subject_id = x.subject_id
		where x.agent_id <> s.pred_id
			and x.agent_id in (select pred_id from subjects where pred_id is not null)

-- @fact
	declare @fact table(row_id int identity primary key, findoc_id int, inout int, article_id int, value decimal(18,2))
		insert into @fact(article_id, findoc_id, inout, value)
		select article_id, findoc_id, inout, sum(fact_dds)
		from (
			select 
				findoc_id,
				article_id,
				case 
					when d_doc < @rep_d_from then -1
					when d_doc between @rep_d_from and @rep_d_to then 0
					else 1
				end as inout,
				fact_dds
			from @findocs
			where internal = 0
			) x
		group by x.article_id, x.findoc_id, x.inout

-- fifo
	declare @left fifo_request
	declare @right fifo_request

	-- @left, @right
	insert into @left(row_id, group_id, value) select row_id, article_id, abs(value) from @plan
	insert into @right(row_id, group_id, value) select row_id, article_id, abs(value) from @fact

	-- calc
	declare @result fifo_response
	insert into @result exec fifo_calc @left, @right

-- update target	
	delete from projects_reps_budgets_pays where rep_id = @report_id

	insert into projects_reps_budgets_pays(rep_id, article_id, findoc_id, plan_inout, fact_inout, fact_bds)
	select @report_id, p.article_id, f.findoc_id, p.inout, f.inout,
		(case when p.value > 0 then 1 else -1 end) * r.value
	from @result r
		inner join @plan p on p.row_id = r.left_row_id
		inner join @fact f on f.row_id = r.right_row_id

end
go