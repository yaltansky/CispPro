if object_id('budget_article_add') is not null drop proc budget_article_add
go
create proc budget_article_add
	@budget_id int,
	@article_id int = null
as
begin

	set nocount on;

	create table #nodes (article_id int, node hierarchyid)
	create index ix_nodes on #nodes(article_id)

	if object_id('tempdb.dbo.#articles') is not null
		insert into #nodes(article_id, node)
			select article_id, node from bdr_articles where article_id in (select article_id from #articles)
	else 
		insert into #nodes(article_id, node)
		select article_id, node from bdr_articles where article_id = @article_id

	delete from #nodes
	where article_id in (select article_id from budgets_articles where budget_id = @budget_id)

	-- all parents
	insert into #nodes(article_id)
	select a.article_id
	from bdr_articles a, #nodes aa
	where aa.node.IsDescendantOf(a.node) = 1

	-- all childs
	insert into #nodes(article_id)
	select a.article_id
	from bdr_articles a, #nodes aa
	where a.node.IsDescendantOf(aa.node) = 1

	delete from #nodes
	where article_id in (select article_id from budgets_articles where budget_id = @budget_id)
	
	insert into budgets_articles(budget_id, parent_id, article_id)
	select @budget_id, a.parent_id, a.article_id
	from bdr_articles a
	where a.article_id in (select distinct article_id from #nodes)
	
end
GO
