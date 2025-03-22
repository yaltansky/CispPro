if object_id('finance_reps_bgoper_planfact') is not null drop proc finance_reps_bgoper_planfact
go
-- exec finance_reps_bgoper_planfact 1000, -1
create proc finance_reps_bgoper_planfact
	@mol_id int,
	@folder_id int
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- access
	if dbo.isinrole(@mol_id, 'Admin,Finance.Admin,Finance.Budgets.Admin') = 0
	begin
		raiserror('У Вас нет доступа к данным выбранного контекста.', 16, 1)
		return
	end

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'BDG'

	select 
		budget_name = b.name,
		goal_account_name = fa.name,
		article_group_name = a2.name,
		article_name = a.name,
		account_name = acc.name,
		x.d_doc,
		x.period_id,
		x.week_id,
		x.value_plan,
		x.value_fact,
		budget_hid = concat('#', b.budget_id)
	from budgets_planfact x
		join @ids i on i.id = x.budget_id
		join budgets b on b.budget_id = x.budget_id
		left join bdr_articles a on a.article_id = x.article_id
			left join bdr_articles a2 on a2.article_id = a.parent_id
		left join fin_goals_accounts fa on fa.goal_account_id = x.goal_account_id
		left join findocs_accounts acc on acc.account_id = x.account_id
end
go
