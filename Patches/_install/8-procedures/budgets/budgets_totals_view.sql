if object_id('budgets_totals_view') is not null	drop proc budgets_totals_view
go
-- exec budgets_totals_view 3, 7
create proc budgets_totals_view
	@budget_id int,
	@goal_account_id int = 0,
	@article_id int = null,
	@ids varchar(max) = null,
	@hide_zero bit = 0,
	@search varchar(250) = null
as
begin

	set nocount on;

	declare @result table (id int, node hierarchyid)

	insert into @result(id, node)
	select id, node
	from budgets_totals
	where budget_id = @budget_id
		and goal_account_id = @goal_account_id
		and (@article_id is null or article_id = @article_id)
		and (@search is null or charindex(@search,name) > 0)
		and (@ids is null or id in (select item from dbo.str2rows(@ids,',')))
		and has_childs = 0
		and (@hide_zero = 0 or (plan_dds <> 0 or fact_dds <> 0))

	-- get all parents
	insert into @result(id, node)
		select distinct x.id, x.node
		from budgets_totals x
			inner join @result r on r.node.IsDescendantOf(x.node) = 1
		where x.budget_id = @budget_id
			and x.goal_account_id = @goal_account_id
			and x.has_childs = 1
			and x.is_deleted = 0

	select node_id = article_id, * from budgets_totals
	where id in (select id from @result)
	order by node
end
GO
