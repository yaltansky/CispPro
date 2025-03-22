if object_id('project_tasks_clear') is not null drop proc project_tasks_clear
go

create proc [dbo].[project_tasks_clear]
	@project_id int,
	@parent_id int = null
as
begin

	set nocount on;

	if @parent_id is null
	begin
		-- delete all tasks
		delete from projects_tasks where project_id = @project_id
		delete from projects_tasks_links where project_id = @project_id
	end

	else 
	begin

		-- delete all childs
		declare @tasks table(task_id int)
		;with tree as (
			select parent_id, task_id 
			from projects_tasks t
			where project_id = @project_id and parent_id = @parent_id
			union all
			select t.parent_id, t.task_id
			from projects_tasks t
				inner join tree s on s.task_id = t.parent_id
			where project_id = @project_id
			)
			insert into @tasks(task_id) select task_id from tree

		delete from projects_tasks where task_id in (select task_id from @tasks)
		delete from projects_tasks_links where source_id in (select task_id from @tasks)
		delete from projects_tasks_links where target_id in (select task_id from @tasks)

	end
		
end
GO
