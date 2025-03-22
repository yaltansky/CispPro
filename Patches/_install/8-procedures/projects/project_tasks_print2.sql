if object_id('project_tasks_print2') is not null drop proc project_tasks_print2
go
create proc project_tasks_print2
	@mol_id int,
	@project_id int,
	@numbers varchar(max)
as
begin

	SET NOCOUNT ON;
	SET ANSI_WARNINGS OFF;

	declare @tree_id int = (select tree_id from trees where type_id = 1 and obj_id = @project_id)

	declare @numbers_table table(task_number int)
		insert into @numbers_table
		select item
		from dbo.str2rows(@numbers, ',')

	create table #tasks (task_id int primary key)
	insert into #tasks
	select t.task_id
	from projects_tasks t
		inner join (
			select project_id, node from projects_tasks		
			where project_id = @project_id
				and task_number in (select task_number from @numbers_table)
		) n on n.project_id = t.project_id
	where t.node.IsDescendantOf(n.node) = 1

	declare @result table (
		section_name varchar(50),
		name varchar(250),
		budget_bdr decimal(18,2),
		budget_bds decimal(18,2),
		resource_q decimal(18,2),
		resource_price decimal(18,2),
		resource_v decimal(18,2)
	)

	insert into @result(section_name, name, budget_bdr, budget_bds)
	select
		'budget',
		ba.name,
		sum(tb.plan_bdr) as plan_bdr,
		sum(tb.plan_dds) as plan_dds
	from projects_tasks_budgets tb
		inner join #tasks t on t.task_id = tb.task_id
		inner join bdr_articles ba on ba.article_id = tb.article_id
	where tb.project_id = @project_id
	group by ba.name

	insert into @result(section_name, name, resource_q, resource_price, resource_v)
	select
		'resource',
		res.name,
		sum(r.quantity),
		max(lim.price),
		sum(r.quantity * lim.price)
	from projects_tasks_resources r
		join projects_resources res on res.resource_id = r.resource_id
		join #tasks t on t.task_id = r.task_id
		join projects_resources_limits lim on lim.tree_id = @tree_id and lim.resource_id = res.resource_id
	group by res.name

	select @project_id as project_id, * from @result
	order by section_name, name

end
go
