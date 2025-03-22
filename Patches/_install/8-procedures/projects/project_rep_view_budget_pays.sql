if object_id('project_rep_view_budget_pays') is not null drop proc project_rep_view_budget_pays
go
create proc project_rep_view_budget_pays
	@mol_id int,
	@report_id int,
	@article_id int = null,
	@inout_plan int = null,
	@inout_fact int = null
as
begin

	set nocount on;

	select
        A.ARTICLE_ID,
        ARTICLE_NAME = A.NAME,
        FD.FINDOC_ID,
        FD.NUMBER,
        FD.D_DOC,
        ACCOUNT_NAME = FA.NAME,
        AGENT_NAME = AG.NAME,
        FD.NOTE,
        P.PLAN_INOUT,
        P.FACT_INOUT,
        FD.VALUE_RUR,
        P.FACT_BDS
	from projects_reps_budgets_pays p
		inner join findocs fd on fd.findoc_id = p.findoc_id
            left join agents ag on ag.agent_id = fd.agent_id
			left join findocs_accounts fa on fa.account_id = fd.account_id
		inner join bdr_articles a on a.article_id = p.article_id
	where p.rep_id = @report_id
		and (@article_id is null or p.article_id = @article_id)
		and (@inout_plan is null or p.plan_inout = @inout_plan)
		and (@inout_fact is null or p.fact_inout = @inout_fact)

end
go
