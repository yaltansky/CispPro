if object_id('sdocs_goal_view') is not null drop procedure sdocs_goal_view
go
-- exec sdocs_goal_view 700, 1
create proc sdocs_goal_view
	@mol_id int,
	@goal_id int,
	@group_id varchar(32) = 'sdocs_by_depts',
	@parent_id int = null,	
	@search varchar(50) = null,
	@ids varchar(max) = null,
	@extra_id varchar(20) = null
as
begin
	
	set nocount on;
	
	-- @node_ids
	declare @node_ids table(node_id int primary key)
	if @ids is not null insert into @node_ids select distinct item from dbo.str2rows(@ids, ',')

	declare @result table(node_id int, node hierarchyid)

	if @ids is not null
	begin		
		-- root
		insert into @result(node_id, node)
		select node_id, node from sdocs_goals_sums 
		where goal_id = @goal_id
			and mol_id = @mol_id
			and group_id = @group_id
			and parent_id is null

		-- expanded parents
		insert into @result(node_id, node)
		select d.node_id, d.node
		from sdocs_goals_sums d
		where d.goal_id = @goal_id
			and d.mol_id = @mol_id
			and d.group_id = @group_id
			and exists(select 1 from @node_ids where node_id = d.node_id)
			and not exists(select 1 from @result where node_id = d.node_id)
		
		-- + their childs
		insert into @result(node_id, node)
		select d.node_id, d.node
		from sdocs_goals_sums d
			inner join @node_ids ids on ids.node_id = d.parent_id
		where d.goal_id = @goal_id
			and d.mol_id = @mol_id
			and d.group_id = @group_id
	end

	else if @search is not null
		or @extra_id is not null
	begin
		declare @d_from datetime, @d_to datetime, @stock_id int
		exec sdocs_goal_params @mol_id, @goal_id, @d_from out, @d_to out, @stock_id out

		-- search
		insert into @result(node_id, node)
		select x.node_id, x.node
		from sdocs_goals_sums x
		where x.goal_id = @goal_id			
			and x.mol_id = @mol_id
			and x.group_id = @group_id
			and x.has_childs = 0
			and (@search is null or x.name like '%' + @search + '%')
			and (
				@extra_id is null
				or (@extra_id = 'ord_start' and x.d_order < @d_from and x.q_order > isnull(x.q_ship,0))
				or (@extra_id = 'ord_new' and x.d_order between @d_from and @d_to)
				or (@extra_id = 'ord_end' and x.q_order > isnull(x.q_ship,0))
			)

		-- + parents
		insert into @result(node_id, node)
			select distinct d.node_id, d.node
			from sdocs_goals_sums d
				join @result r on r.node.IsDescendantOf(d.node) = 1
			where d.goal_id = @goal_id
				and d.mol_id = @mol_id
				and d.group_id = @group_id
				and d.has_childs = 1
	end	

	else begin
		
		insert into @result
		select d.node_id, d.node
		from sdocs_goals_sums d
		where goal_id = @goal_id	
			and d.mol_id = @mol_id
			and d.group_id = @group_id
			and (
				(@parent_id is null and level_id <= 1)
				or parent_id = @parent_id
				)
	end

	select d.* into #sums
	from sdocs_goals_sums d
	where d.goal_id = @goal_id
		and d.mol_id = @mol_id
		and d.group_id = @group_id
		and d.node_id in (select distinct node_id from @result)
	
	exec sdocs_goal_calc;30 -- process #sums

-- calc totals
	select * from #sums	order by node

end
go