if object_id('budgets_by_vendors_calc') is not null drop proc budgets_by_vendors_calc
go
create proc budgets_by_vendors_calc
	@news_only bit = 0
as
begin

	set nocount on;

-- build
	if @news_only = 0
		delete from budgets_by_vendors

	declare @budgets table(subject_id int, budget_id int primary key, project_id int, name varchar(255))
	
	-- бюджеты сделок
	insert into @budgets(subject_id, budget_id, project_id, name)
	select d.vendor_id, b.budget_id, b.project_id, b.name
	from budgets b
		join deals d on d.budget_id = b.budget_id
	where (@news_only = 0
		or b.budget_id not in (select budget_id from budgets_by_vendors)
		)
		and b.is_deleted = 0

	-- 0
	if @news_only = 0
		insert into @budgets(subject_id, budget_id, name)
		select 0, budget_id, name
		from budgets
		where budget_id = (select main_id from budgets where budget_id = 0)

	declare @min_id int = (select min(budget_id) from budgets)
	
	if @news_only = 0
		insert into budgets_by_vendors(subject_id, budget_id, name, has_childs)
		select 
			subject_id,
			@min_id - (row_number() over (order by name) + 1),
			name,
			1
		from subjects

	insert into budgets_by_vendors(parent_id, budget_id, project_id, name)
	select bb.budget_id, b.budget_id, b.project_id, b.name
	from @budgets b
		join budgets_by_vendors bb on bb.subject_id = b.subject_id

	declare @budgets_misc table(budget_id int primary key, name varchar(255), project_id int)
	
	if @news_only = 0
	begin
		insert into @budgets_misc(budget_id, name, project_id)
		select budget_id, name, project_id
		from budgets
		where budget_id not in (select budget_id from @budgets)
			and is_deleted = 0

		declare @parent_id int
	
		-- добавить бюджеты проектов
		set @parent_id = (select min(budget_id) from budgets) - 1
		insert into budgets_by_vendors(budget_id, name, has_childs)
		select @parent_id, 'Проекты', 1

		insert into budgets_by_vendors(parent_id, budget_id, name)
		select @parent_id, budget_id, name
		from @budgets_misc
		where project_id is not null
	
		-- остальные бюджеты - в прочее
		set @parent_id = (select min(budget_id) from budgets_by_vendors) - 1
	
		insert into budgets_by_vendors(budget_id, name, has_childs)
		select @parent_id, 'Прочие', 1

		insert into budgets_by_vendors(parent_id, budget_id, name)
		select @parent_id, budget_id, name
		from @budgets_misc
		where project_id is null
	end

-- hierarchyid
	if @news_only = 1
	begin
		-- set node = null for selected childs and their parents
		;with tree as (
			select parent_id, budget_id from budgets_by_vendors where node is null and is_deleted = 0
			union all
			select x.parent_id, x.budget_id 
			from budgets_by_vendors x
				join tree on tree.parent_id = x.budget_id
			where x.is_deleted = 0
			)
			update x set node = null from budgets_by_vendors x 
				join tree on tree.budget_id = x.budget_id
	end

	create table #children(node_id int primary key, parent_id int, num int)
		insert #children (node_id, parent_id, num)
		select budget_id, parent_id,  
		  row_number() over (partition by parent_id order by parent_id, has_childs desc, name)
		from budgets_by_vendors where is_deleted = 0
			and (@news_only = 0 or node is null)

	create table #nodes(node_id int primary key, node hierarchyid)		

	;with paths(node_id, node)
	as (  
		select node_id, cast(concat('/', c.num, '/') as hierarchyid) as node
		from #children c
		where parent_id is null

		union all   
		select c.node_id, cast(concat(p.node.ToString(), c.num, '/') as hierarchyid)
		from #children as c
			join paths as p on c.parent_id = p.node_id
		)  
	insert into #nodes(node_id, node) select node_id, node from paths

	update x
	set node = n.node,
		level_id = n.node.GetLevel()
	from budgets_by_vendors x
		join #nodes as n on n.node_id = x.budget_id

	drop table #children, #nodes
end
GO
