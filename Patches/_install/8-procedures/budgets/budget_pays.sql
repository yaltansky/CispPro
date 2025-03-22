if object_id('budget_pays') is not null drop proc budget_pays
go
-- exec budget_pays -663215
create proc budget_pays
	@budget_id int
as
begin
	
	set nocount on;

-- #articles
	create table #articles (row_id int identity, article_id int primary key, name varchar(250), fact_dds decimal)

	insert into #articles(article_id, name, fact_dds)
	select a.article_id, a.name, b.fact_dds
	from budgets_totals b
		join bdr_articles a on a.article_id = b.article_id
	where b.budget_id = @budget_id
		and a.has_childs = 0
		and cast(isnull(b.fact_dds,0) as decimal) <> 0
	order by a.node

-- @subjects
	declare @subjects table(subject_id int)
	insert into @subjects select subject_id from budgets_subjects where budget_id = @budget_id

-- @to_date	
	declare @to_date datetime = (select max(date_end) from budgets_periods where budget_id = @budget_id and is_selected = 1)

	select
		A.ARTICLE_ID,
		A.NAME AS ARTICLE_NAME,
		A.FACT_DDS,
		S.NAME AS SUBJECT_NAME,
		S.SHORT_NAME AS SUBJECT_SHORT_NAME,
		F.D_DOC,
		FF.NUMBER,
		ACC.NAME AS ACCOUNT_NAME,
		AG.NAME AS AGENT_NAME,
		F.VALUE_RUR,
		FF.NOTE
	from findocs# f
		join findocs ff on ff.findoc_id = f.findoc_id
			join @subjects ss on ss.subject_id = ff.subject_id
			left join subjects s on s.subject_id = ff.subject_id
			left join findocs_accounts acc on acc.account_id = ff.account_id
			left join agents ag on ag.agent_id= ff.agent_id
		join #articles a on a.article_id = f.article_id
	where f.budget_id = @budget_id
		and f.d_doc <= @to_date
	order by a.row_id, f.d_doc

end
go
