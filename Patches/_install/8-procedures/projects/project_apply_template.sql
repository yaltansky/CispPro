if object_id('project_apply_template') is not null drop proc project_apply_template
go
create proc project_apply_template
	@project_id int
as
begin

	set nocount on;

	if exists(select 1 from projects_tasks where project_id = @project_id and is_deleted = 0)
	begin
		raiserror('Раздел "Работы" содержит операции. Применение шаблона невозможно.', 16, 1)
		return
	end

	declare @template_id int = (select template_id from projects where project_id = @project_id)
	declare @map table(source_id int primary key, target_id int)

	BEGIN TRY
	BEGIN TRANSACTION

	-- copy tasks
		delete @map;
		delete from projects_tasks where project_id = @project_id

		insert into projects_tasks(
			project_id, template_task_id, status_id, task_number, name, d_from, d_to, d_after, d_before, predecessors, duration, duration_input, duration_fact, duration_id, duration_buffer, is_node, is_critical, is_long, is_overlong, execute_level, node, parent_id, outline_level, has_childs, sort_id, is_deleted, description, priority_id, tags
			)
			output inserted.template_task_id, inserted.task_id into @map
		select 
			@project_id, task_id, status_id, task_number, name, d_from, d_to, d_after, d_before, predecessors, duration, duration_input, duration_fact, duration_id, duration_buffer, is_node, is_critical, is_long, is_overlong, execute_level, node, parent_id, outline_level, has_childs, sort_id, is_deleted, description, priority_id, tags
		from projects_tasks t
		where project_id = @template_id

		update x
		set parent_id = m.target_id
		from projects_tasks x
			inner join @map m on m.source_id = x.parent_id
		where x.project_id = @project_id

	-- copy links
		exec project_tasks_calc_links @project_id = @project_id

	-- copy resources
		insert into projects_tasks_resources(task_id, resource_id, quantity, mol_id, note, add_date)
		select m.target_id, resource_id, quantity, mol_id, note, getdate()
		from projects_tasks_resources r
			inner join @map m on m.source_id = r.task_id

	-- copy budgets
		declare @template_budget_id int = (select top 1 budget_id from projects_tasks_budgets where project_id = @template_id)

		insert into budgets(status_id, name, note, project_id, is_wbs, mol_id)
		select x.status_id, 'Бюджет ' + p.name, x.note, @project_id, x.is_wbs, x.mol_id
		from budgets x, projects p
		where x.budget_id = @template_budget_id
			and p.project_id = @project_id
		
		declare @budget_id int = @@identity

		-- budgets_articles
		insert into budgets_articles(budget_id, parent_id, article_id, paydelay)
			select @budget_id, parent_id, article_id, paydelay
			from budgets_articles where budget_id = @template_budget_id

		-- budgets_periods
		insert into budgets_periods(budget_id, bdr_period_id, name, date_start, date_end, is_deleted)
			select @budget_id, bdr_period_id, name, date_start, date_end, is_deleted
			from budgets_periods where budget_id = @template_budget_id

		-- budgets_subjects
		insert into budgets_subjects(budget_id, subject_id)
			select @budget_id, subject_id
			from budgets_subjects where budget_id = @template_budget_id

	-- copy budgets-wbs
		declare @map2 table(source_id int primary key, target_id int)

		insert into projects_tasks_budgets(template_ref_id, project_id, budget_id, task_id, article_id, plan_bdr, plan_dds, note, mol_id)
			output inserted.template_ref_id, inserted.id into @map2
		select r.id, @project_id, @budget_id, m.target_id, r.article_id, plan_bdr, plan_dds, note, mol_id
		from projects_tasks_budgets r
			inner join @map m on m.source_id = r.task_id
		where r.project_id = @template_id

		insert into projects_tasks_budgets_details(parent_id, date_type_id, date_lag, d_doc, plan_bdr, plan_dds, note)
		select m.target_id, r.date_type_id, r.date_lag, r.d_doc, r.plan_bdr, r.plan_dds, r.note
		from projects_tasks_budgets_details r
			inner join @map2 m on m.source_id = r.parent_id

	-- mols
		delete @map;

		insert into projects_mols(
			project_id, reserved, mol_id, response, post_name, add_date, duration, account_level_id, name, parent_id, has_childs, level_id, sort_id, node, is_deleted
			)
			output inserted.reserved, inserted.id into @map
		select 
			@project_id, id, mol_id, response, post_name, add_date, duration, account_level_id, name, parent_id, has_childs, level_id, sort_id, node, is_deleted
		from projects_mols
		where project_id = @template_id

		update x
		set parent_id = m.target_id
		from projects_mols x
			inner join @map m on m.source_id = x.parent_id
		where x.project_id = @project_id

		insert into projects_mols_sections_meta (
			project_id, tree_id, section_id, a_read, a_update
			)
		select @project_id, m.target_id, section_id, a_read, a_update
		from projects_mols_sections_meta x
			inner join @map m on m.source_id = x.TREE_ID
		where project_id = @template_id

		exec project_mols_calc @project_id

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH

end
GO
