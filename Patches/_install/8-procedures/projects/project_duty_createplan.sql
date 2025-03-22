if object_id('project_duty_createplan') is not null drop proc project_duty_createplan
go
create proc project_duty_createplan
	@project_id int,
	@mol_id int -- for future use
as
begin

	set nocount on;

	if exists(select 1 from projects_tasks where project_id = @project_id and status_id <> -1)
	begin
		raiserror('Текущий план содержит операции. Для создания плана из обязательств необходимо предварительно очистить план.', 16, 1)
		return
	end

	declare @tasks table (
		project_id int,
		parent_id int,
		duty_id int,
		task_id int,
		name varchar(250),
		d_from datetime,
		d_to datetime,
		has_childs bit,
		sort_id float,
		level_id int
	)

	declare @maxid int; select @maxid = max(task_id) from projects_tasks

	-- @tasks
	insert into @tasks
		select p.project_id, p.parent_id, p.task_id,
			@maxid + row_number() over (order by p.sort_id),
			p.name, p.d_from, p.d_to, p.has_childs, p.sort_id, p.level_id			
		from projects_duties p
		where p.project_id = @project_id
			and is_deleted = 0

	-- projects_tasks
	SET IDENTITY_INSERT CISP_SHARED..PROJECTS_TASKS ON;

		insert into projects_tasks (
			project_id, parent_id, task_id, task_number, name, d_from, d_to,
			has_childs, sort_id, outline_level
			)
		select
			t.project_id, tt.task_id, t.task_id,
			row_number() over (order by t.task_id),
			t.name, t.d_from, t.d_to,
			t.has_childs,
			row_number() over (order by t.task_id),
			t.level_id
		from @tasks t
			left join @tasks tt on tt.duty_id = t.parent_id
	
	SET IDENTITY_INSERT CISP_SHARED..PROJECTS_TASKS OFF;

	-- TASK_ID refs
	update pd
	set task_id = t.task_id
	from projects_duties pd
		inner join @tasks t on t.duty_id = pd.task_id
	
	exec project_tasks_calc @project_id = @project_id

end
go
