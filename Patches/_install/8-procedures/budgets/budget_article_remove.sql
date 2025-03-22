if object_id('budget_article_remove') is not null drop proc budget_article_remove
go
create proc budget_article_remove
	@budget_id int,
	@article_id int
as
begin

	set nocount on;

	declare @articles table (article_id int)

	-- and all childs
	;with s as (
		select parent_id, article_id from bdr_articles where article_id = @article_id
		union all
		select t.parent_id, t.article_id
		from bdr_articles t
			inner join s on s.article_id = t.parent_id
		)
		insert into @articles(article_id) select article_id from s

	delete from budgets_articles
	where budget_id = @budget_id
		and article_id in (select article_id from @articles)

end
GO
