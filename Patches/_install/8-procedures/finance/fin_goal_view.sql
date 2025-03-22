if object_id('fin_goal_view') is not null drop procedure fin_goal_view
go
create proc fin_goal_view
	@mol_id int,
	@fin_goal_id int,
	@group_id varchar(32),
	@parent_id int = null,	
	@search varchar(50) = null,
	@ids varchar(max) = null,
	@extra_id int = null
as
begin
	
	set nocount on;
	
	if not exists(
		select 1 from fin_goals_sums where fin_goal_id = @fin_goal_id and mol_id = @mol_id and group_id = @group_id
		)
	begin
		-- auto-calc
		exec fin_goal_calc;10 @fin_goal_id = @fin_goal_id, @mol_id = @mol_id, @group_id = @group_id
	end

	-- @node_ids
	declare @node_ids table(node_id int primary key)
	if @ids is not null insert into @node_ids select distinct item from dbo.str2rows(@ids, ',')

	declare @result table(node_id int, node hierarchyid)

	if @ids is not null
	begin		
		-- root
		insert into @result(node_id, node)
		select node_id, node from fin_goals_sums 
		where fin_goal_id = @fin_goal_id
			and mol_id = @mol_id
			and group_id = @group_id
			and parent_id is null

		-- expanded parents
		insert into @result(node_id, node)
		select d.node_id, d.node
		from fin_goals_sums d
		where d.fin_goal_id = @fin_goal_id
			and d.mol_id = @mol_id
			and d.group_id = @group_id
			and exists(select 1 from @node_ids where node_id = d.node_id)
			and not exists(select 1 from @result where node_id = d.node_id)
		
		-- + their childs
		insert into @result(node_id, node)
		select d.node_id, d.node
		from fin_goals_sums d
			inner join @node_ids ids on ids.node_id = d.parent_id
		where d.fin_goal_id = @fin_goal_id
			and d.mol_id = @mol_id
			and d.group_id = @group_id
	end

	else if @search is not null
		or @extra_id is not null
	begin
		-- search
		insert into @result(node_id, node)
		select d.node_id, d.node
		from fin_goals_sums d
		where d.fin_goal_id = @fin_goal_id			
			and d.mol_id = @mol_id
			and d.group_id = @group_id
			and (@search is null or d.name like '%' + @search + '%')
			and (@extra_id is null
				or (@extra_id = 1 and abs(d.value_in + d.value_out) > 10)
			)

		-- + parents
		insert into @result(node_id, node)
			select distinct d.node_id, d.node
			from fin_goals_sums d
				join @result r on r.node.IsDescendantOf(d.node) = 1
			where d.fin_goal_id = @fin_goal_id
				and d.mol_id = @mol_id
				and d.group_id = @group_id
				and d.has_childs = 1
	end	

	else begin
		
		declare @folder_id int = (select folder_id from fin_goals where fin_goal_id = @fin_goal_id)

		insert into @result
		select d.node_id, d.node
		from fin_goals_sums d
		where fin_goal_id = @fin_goal_id	
			and d.mol_id = @mol_id
			and d.group_id = @group_id
			and (
				@parent_id is null
				or parent_id = @parent_id
				)
	end

-- return results	
	select 
		D.ID,
		D.FIN_GOAL_ID,
		D.FOLDER_ID,
		D.GOAL_ACCOUNT_ID,
		D.ARTICLE_ID,
		D.BUDGET_ID,
		B.PROJECT_ID,
		--
		D.NODE,
		D.NODE_ID,
		D.PARENT_ID,
		D.HAS_CHILDS,
		D.LEVEL_ID,
		--
        D.NAME,
		D.EXCLUDED,
		D.VALUE_START,
		D.VALUE_IN,
		D.VALUE_OUT,
		D.VALUE_END,
		D.VALUE_IN_EXCL,
		D.VALUE_OUT_EXCL
	into #sums
	from fin_goals_sums d
		left join budgets b on b.budget_id = d.budget_id
	where d.fin_goal_id = @fin_goal_id
		and d.mol_id = @mol_id
		and d.group_id = @group_id
		and d.node_id in (select distinct node_id from @result)

	exec fin_goal_calc;30 -- process #sums

-- calc totals
	select * from #sums	order by node
end
go