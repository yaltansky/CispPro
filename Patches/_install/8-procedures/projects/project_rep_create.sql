if object_id('project_rep_create') is not null
	drop proc project_rep_create
go
create proc project_rep_create
	@report_id int
as
begin

	set nocount on;

	declare 
		@project_id int,
		@rep_type_id int,
		@d_from datetime, @d_to datetime
	
	select
		@project_id = project_id,
		@d_from = d_from,
		@d_to = d_to,
		@rep_type_id = rep_type_id
	from projects_reps where rep_id = @report_id

	if exists(select 1 from projects_reps_tasks	where rep_id = @report_id)
	begin
		update projects_reps set status_id = 1 where rep_id = @report_id
		raiserror('Оперативный план был ранее создан, поэтому он переведён в статус "Исполнение".', 16, 1)
		return
	end

	-- null duration
	update projects_tasks set duration = 0 where project_id = @project_id and duration is null

	-- auto-close previous reports
	declare @prev_rep_id int; select @prev_rep_id = max(rep_id) from projects_reps where project_id = @project_id and rep_type_id = @rep_type_id
		and rep_id <> @report_id
		and status_id not in (-1,10)

	if @prev_rep_id is not null 
	begin
		exec project_rep_calc @report_id = @prev_rep_id
		--
		update projects_reps
		set status_id = 10
		where rep_id = @prev_rep_id
	end

	else begin 
		exec project_tasks_calc @project_id = @project_id
	end

-- PROJECTS_REPS_TASKS
	-- Очистить
	delete from projects_reps_tasks	where rep_id = @report_id

	-- копия плана
	insert into projects_reps_tasks(
		rep_id, task_id,
		d_from, d_to, d_to_current, wk_d_from, wk_d_to, d_after, d_before, d_from_fact, d_to_fact,
		duration, duration_input, duration_id, duration_buffer, duration_fact,
		progress, progress_current,
		task_number, name, predecessors,
		parent_id, is_node, has_childs, sort_id, outline_level,
		is_long, is_critical, is_overlong, execute_level,
		priority_id, tags, has_files,
		count_checks, count_checks_all,
		old_d_from, old_d_to,
		talk_id
		)
	select 
		@report_id, task_id,
		d_from, d_to, d_to, wk_d_from, wk_d_to, d_after, d_before, d_from_fact, d_to_fact,
		duration, duration_input, duration_id, duration_buffer, duration_fact,
		progress, progress,
		task_number, name, predecessors,
		parent_id, is_node, has_childs, sort_id, outline_level,
		is_long, is_critical, is_overlong, execute_level,
		priority_id, tags, has_files,
		count_checks, count_checks_all,
		d_from, d_to,
		talk_id
	from projects_tasks
	where project_id = @project_id

-- PROJECTS_TASKS_BUDGETS, PROJECTS_TASKS_BUDGETS_DETAILS
	declare @budget_id int = (select top 1 budget_id from budgets where project_id = @project_id and is_deleted = 0)
	if @budget_id is not null 
	begin
		exec budget_calc @budget_id = @budget_id

		delete from projects_reps_budgets where rep_id = @report_id

		insert into projects_reps_budgets(rep_id, project_id, budget_id, task_id, article_id, d_doc, inout, plan_bds, note)
		select @report_id, project_id, budget_id, task_id, article_id, d_doc_calc, 
			case 
				when d_doc_calc < @d_from then -1
				when d_doc_calc between @d_from and @d_to then 0
				else 1
			end,
			plan_dds, note
		from v_projects_tasks_budgets
		where project_id = @project_id
			and abs(plan_dds) >= 0.01
	end

	exec project_rep_calc @report_id = @report_id

-- change status
	update projects_reps 
	set status_id = 1
	where rep_id = @report_id

end
go