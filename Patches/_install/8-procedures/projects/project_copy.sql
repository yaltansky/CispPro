if exists(select 1 from sys.objects where name = 'project_copy')
	drop proc project_copy
go
create proc project_copy
	@project_id int
as
begin

	set nocount on;

	declare @to_project_id int
	declare @map table(source_id int primary key, target_id int)

	BEGIN TRY
	BEGIN TRANSACTION

	-- project
		insert into projects(
			group_id, name, goal, curator_id, admin_id, chief_id, d_from, d_to, d_to_min, status_id, note, ccy_id, plan_ccy, fact_ccy, progress, progress_critical, progress_exec, progress_speed, progress_lag, add_date, update_date, update_mol_id, d_to_forecast, lock_date, lock_mol_id, calc_loops, refkey
			)
		select
			group_id, name + ' (копия)', goal, curator_id, admin_id, chief_id, d_from, d_to, d_to_min, status_id, note, ccy_id, plan_ccy, fact_ccy, progress, progress_critical, progress_exec, progress_speed, progress_lag, add_date, update_date, update_mol_id, d_to_forecast, lock_date, lock_mol_id, calc_loops, refkey
		from projects
		where project_id = @project_id

		set @to_project_id = @@identity

	-- mols
		delete @map;
		insert into projects_mols(
			project_id, reserved, mol_id, response, post_name, add_date, duration, account_level_id, name, parent_id, has_childs, level_id, sort_id, node, is_deleted
			)
			output inserted.reserved, inserted.id into @map
		select 
			@to_project_id, id, mol_id, response, post_name, add_date, duration, account_level_id, name, parent_id, has_childs, level_id, sort_id, node, is_deleted
		from projects_mols
		where project_id = @project_id

		update x
		set parent_id = m.target_id
		from projects_mols x
			inner join @map m on m.source_id = x.parent_id

	-- tasks
		delete @map;
		insert into projects_tasks(
			project_id, reserved, status_id, task_number, name, d_from, d_to, wk_d_from, wk_d_to, d_from_fact, d_to_fact, d_after, d_before, predecessors, duration, duration_input, duration_fact, duration_id, duration_buffer, progress, d_progress_completed, is_node, is_critical, is_long, is_overlong, execute_level, node, parent_id, outline_level, has_childs, sort_id, is_deleted, description, priority_id, tags, has_files, count_raci, add_date, update_date, update_mol_id, d_from_duty, d_to_duty
			)
			output inserted.reserved, inserted.task_id into @map
		select 
			@to_project_id, task_id, status_id, task_number, name, d_from, d_to, wk_d_from, wk_d_to, d_from_fact, d_to_fact, d_after, d_before, predecessors, duration, duration_input, duration_fact, duration_id, duration_buffer, progress, d_progress_completed, is_node, is_critical, is_long, is_overlong, execute_level, node, parent_id, outline_level, has_childs, sort_id, is_deleted, description, priority_id, tags, has_files, count_raci, add_date, update_date, update_mol_id, d_from_duty, d_to_duty
		from projects_tasks t
		where project_id = @project_id

		update x
		set parent_id = m.target_id
		from projects_tasks x
			inner join @map m on m.source_id = x.parent_id
		where x.project_id = @to_project_id

	-- resources
		insert into projects_tasks_resources(task_id, resource_id, quantity, mol_id, note, add_date)
		select m.target_id, resource_id, quantity, mol_id, note, getdate()
		from projects_tasks_resources r
			inner join @map m on m.source_id = r.task_id

	-- buys
		delete @map;
		insert into projects_buys(
			project_id, reserved_id, name, vendor, note, quantity, netto, brutto, price_rur, plan_rur, parent_id, has_childs, sort_id, level_id, is_deleted, add_date, mol_id, node
			)
			output inserted.reserved_id, inserted.buy_id into @map
		select 
			@to_project_id, buy_id, name, vendor, note, quantity, netto, brutto, price_rur, plan_rur, parent_id, has_childs, sort_id, level_id, is_deleted, add_date, mol_id, node
		from projects_buys b
		where project_id = @project_id

		update x
		set parent_id = m.target_id
		from projects_buys x
			inner join @map m on m.source_id = x.parent_id
		where x.project_id = @to_project_id

	-- links
		exec project_tasks_calc_links @project_id = @to_project_id

	-- trees
		insert into trees		(
			type_id, parent_id, name, description, obj_type, obj_id, has_childs, level_id, sort_id, is_deleted, add_date, node
		)
		select
			type_id, parent_id, name, description, obj_type, @to_project_id, has_childs, level_id, sort_id, is_deleted, add_date, node
		from trees
		where obj_id = @project_id
			and obj_type = 'PRJ'

		exec trees_calc
		
	-- output
		select * from projects where project_id = @to_project_id

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH

end
GO
