if object_id('fin_goals_accounts_search') is not null drop proc fin_goals_accounts_search
go
CREATE proc fin_goals_accounts_search
	@parent_id int = null,
	@search varchar(32) = null
as
begin

	set nocount on;

	declare @result table(
		parent_id int,
		goal_account_id int index ix_budget,
		node hierarchyid
		)
	
	declare @id int = dbo.hashid(@search)
	if @id is not null set @search = null

	set @search = '%' + replace(@search, ' ', '%') + '%'

	-- children
	if @parent_id is not null
		insert into @result(parent_id, goal_account_id, node) 
		select parent_id, goal_account_id, node
		from fin_goals_accounts
		where parent_id = @parent_id
	
	else begin
		-- search
		if @search is not null or @id is not null
			insert into @result(parent_id, goal_account_id, node)
				select top 500 parent_id, goal_account_id, node from fin_goals_accounts
				where (@id is null or goal_account_id = @id)
					and (@search is null or name like @search)
					and is_deleted = 0

		-- top
		else
			insert into @result(parent_id, goal_account_id, node) 
			select parent_id, goal_account_id, node
			from fin_goals_accounts
			where parent_id is null

		-- calc tree: childs + all parents
		insert into @result(parent_id, goal_account_id)
		select b.parent_id, b.goal_account_id
		from fin_goals_accounts b
			join @result r on r.node.IsDescendantOf(b.node) = 1
	end
	
-- return results
	select  top 1000
		x.goal_account_id as node_id,
		x.*,
		m1.name as mol_name,
		m2.name as update_mol_name
	from fin_goals_accounts x
		left join mols m1 on m1.mol_id = x.add_mol_id
		left join mols m2 on m2.mol_id = x.update_mol_id
	where goal_account_id in (select goal_account_id from @result)
		and x.is_deleted = 0
	order by x.node
end
GO
