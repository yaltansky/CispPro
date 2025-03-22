if object_id('project_tasks_checkaccess') is not null drop proc project_tasks_checkaccess
go
create proc project_tasks_checkaccess
	@mol_id int,
	@project_id int,
	@task_id int,
	@allowaccess bit out
as
begin

	declare @node hierarchyid = (select node from projects_tasks where task_id = @task_id)

	set @allowaccess = 
			case 
				when exists(
					select 1
					from projects_tasks_raci
					where task_id in (
						select task_id
						from projects_tasks
						where project_id = @project_id
							and @node.IsDescendantOf(node) = 1				
						) 
						and mol_id = @mol_id
						and (charindex('A', raci) >= 1 or charindex('R', raci) >= 1)
					)
				then 1
				else 0
			end

end
GO
