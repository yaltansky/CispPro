if object_id('project_resources_view') is not null drop proc project_resources_view
go
create proc [project_resources_view]
	@project_id int,
	@resource_id int,
	@search varchar(max) = null,
	@offset int = null,
	@fetchrows int = null,
	@rowscount int out
as
begin

	set nocount on;

	declare @aggregation_id int
	select @aggregation_id = aggregation_id from projects_resources where resource_id = @resource_id

-- @tasks
	declare @tasks table (task_id int)

	insert into @tasks select task_id from projects_tasks 
	where project_id = @project_id and has_childs = 0
		and (@search is null or name like '%' + @search + '%')

-- @resources
	declare @resources table (task_id int, resource_id int, quantity decimal(18,3), note varchar(max))
	insert into @resources(task_id, resource_id, quantity, note)
	select task_id, resource_id, quantity, note from projects_tasks_resources
	where task_id in (select task_id from @tasks)
		and resource_id = @resource_id

	declare @prev table (task_id int primary key)
	declare @level table (task_id int, quantity decimal(18,2))

	-- начальные строки (срез нижнего уровня)
	insert into @prev(task_id)
	select distinct b.task_id from @resources b

	declare @i int; set @i = 0
	while @i < 10 -- страховка: не более 10 итераций!
	begin		
		delete from @level

		-- calc level up
		insert into @level(task_id, quantity)
		select t.parent_id
			, case when @aggregation_id = 1 then sum(quantity) else max(quantity) end
		from @resources b
			inner join projects_tasks t on t.task_id = b.task_id			
		where t.parent_id in (
			select parent_id from projects_tasks
			where task_id in (select task_id from @prev)
			)
		group by t.parent_id

		-- delete
		delete from @resources where task_id in (select task_id from @level)

		-- insert
		insert into @resources(task_id, quantity)
		select task_id, quantity
		from @level

		-- @prev
		delete from @prev
		insert into @prev(task_id) select distinct task_id from @level

		if @@rowcount = 0 break -- это значит добрались до верхнего уровня иерархии
		set @i = @i + 1
	end

	select @rowscount = count(*) from @resources

	select
		@RESOURCE_ID as RESOURCE_ID,
		R.TASK_ID,		
		T.TASK_NUMBER,
		T.NAME,
		T.OUTLINE_LEVEL,
		T.HAS_CHILDS,
		R.QUANTITY,
		R.NOTE
	from @resources r
		inner join projects_tasks t on t.task_id = r.task_id
	order by t.sort_id, t.name

end
GO
