if exists(select 1 from sys.objects where name = 'project_tasks_move')
	drop proc project_tasks_move
go
create proc project_tasks_move
	@mol_id int,
	@node_id int,
	@to_project_id int,
	@make_reference bit = 0
as
begin

	set nocount on;

	declare @project_id int = (select project_id from projects_tasks where task_id = @node_id)
	declare @node hierarchyid = (select node from projects_tasks where task_id = @node_id)

	declare @tasks table(task_id int primary key)
		insert @tasks select task_id from projects_tasks x
		where project_id = @project_id
			and node.IsDescendantOf(@node) = 1

	declare @badlinks table(link_id int)
		insert into @badlinks(link_id)
		select link_id
		from projects_tasks_links
		where source_id in (select task_id from @tasks)
			and target_id not in (select task_id from @tasks)
		UNION ALL
		select link_id
		from projects_tasks_links
		where target_id in (select task_id from @tasks)
			and source_id not in (select task_id from @tasks)

	BEGIN TRY
	BEGIN TRANSACTION

		-- move children
		update projects_tasks
		set project_id = @to_project_id
		where task_id in (select task_id from @tasks)

		-- move links
		update projects_tasks_links
		set project_id = @to_project_id
		where target_id in (select task_id from @tasks)

		-- delete unnecessary links
		delete from projects_tasks_links where link_id in (select link_id from @badlinks)

		-- set root
		update projects_tasks set parent_id = null where task_id = @node_id

		-- projects_tasks_budgets
		update projects_tasks_budgets
		set project_id = @to_project_id
		where task_id in (select task_id from @tasks)

		-- create reference task
		if @make_reference = 1
		begin
			insert into projects_tasks(project_id, ref_project_id, task_number, name, parent_id, node, outline_level, sort_id)
				select @project_id, @to_project_id, task_number, name, parent_id, node, outline_level, sort_id
				from projects_tasks
				where task_id = @node_id
		end
			
	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH

	exec project_tasks_reorder @project_id
	exec project_tasks_reorder @to_project_id

	exec project_tasks_calc @mol_id = @mol_id, @project_id = @project_id
	exec project_tasks_calc @mol_id = @mol_id, @project_id = @to_project_id
end
go
