if object_id('finance_reps_statement') is not null drop proc finance_reps_statement
go
-- exec finance_reps_statement 700, 11688
create proc finance_reps_statement
	@mol_id int,
	@folder_id int,
	@d_from datetime = null,
	@d_to datetime = null
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
-- @subjects
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
-- @budgets
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'

-- @ids
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'fd'

-- result
	select 
		SUBJECT_NAME = s.short_name,
		GOAL_ACCOUNT_NAME = ga.name,
		ACCOUNT_NAME = fa.name,
		AGENT_NAME = ag.name,
		PROJECT_NAME = 
			case
				when p.project_id is null then '<ТЕКУЩАЯ ДЕЯТЕЛЬНОСТЬ>'
				when p.type_id = 3 then '<БЮДЖЕТЫ СДЕЛОК>'
				else p.name
			end,
		BUDGET_NAME = b.name,
		ARTICLE_NAME = a.name,
		F.FINDOC_ID,
		F.D_DOC,
		FF.NOTE,
		VALUE_IN = cast(case when f.value_rur > 0 then f.value_rur end as decimal(18,2)),
		VALUE_OUT = cast(case when f.value_rur < 0 then f.value_rur end as decimal(18,2))
	from findocs# f
		join @ids buf on buf.id = f.findoc_id
		--
		join subjects s on s.subject_id = f.subject_id
		join findocs ff on ff.findoc_id = f.findoc_id
		left join fin_goals_accounts ga on ga.goal_account_id = f.goal_account_id
		join findocs_accounts fa on fa.account_id = f.account_id
		join agents ag on ag.agent_id = f.agent_id
		left join budgets b on b.budget_id = f.budget_id
			left join projects p on p.project_id = b.project_id
		left join bdr_articles a on a.article_id = f.article_id
	where 
		exists(select 1 from @subjects where id = f.subject_id)
		or exists(select 1 from @budgets where id = f.budget_id)

end
go