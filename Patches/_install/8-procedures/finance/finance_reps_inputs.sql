if object_id('finance_reps_inputs') is not null drop proc finance_reps_inputs
go
-- exec finance_reps_inputs 700, 8161
create proc finance_reps_inputs
	@mol_id int,
	@folder_id int,
	@principal_id int = 9
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit =
		case 
			when exists(select 1 from @budgets where id = -1)  and not exists(select 1 from @budgets where id != -1) then 1
			else 0 
		end

	if @all_budgets = 0
	begin
		raiserror('Для данного отчёта необходим доступ ко всем бюджетам (в рамках субъекта учёта).', 16, 1)
		return
	end

-- findocs_mkdetails
	create table #resultInputs(
		row_id int,
		folder_id int,
		vendor_id int,
		budget_id int,
		deal_product_id int,
		article_id int,
		d_doc date,
		findoc_id int index ix_findoc,
		value float,
		value_nds float
		)

-- учёт сделок, проектов
	exec findocs_mkdetails @mol_id = @mol_id, @folder_id = @folder_id

	delete x from #resultInputs x
		join findocs f on f.findoc_id = x.findoc_id
	where f.subject_id not in (select id from @subjects)

-- учёт бюджетов (кроме проектов и сделок)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'fd'

	insert into #resultInputs(
		folder_id, vendor_id, budget_id, article_id, d_doc, findoc_id, value
		)
	select 
		@folder_id, f.subject_id, f.budget_id, f.article_id, f.d_doc, f.findoc_id, f.value_rur
	from findocs# f
		join @subjects s on s.id = f.subject_id
		join @ids i on i.id = f.findoc_id
		join budgets b on b.budget_id = f.budget_id
	where f.value_rur > 0
		and not exists(select 1 from #resultInputs where findoc_id = f.findoc_id and budget_id = f.budget_id)

-- prepare #result
	create table #result(
		CREDIT_TYPE VARCHAR(30) default '2.Не финансировано',
		SUBJECT_NAME VARCHAR(20),
		ACCOUNT_NAME VARCHAR(255),
		D_DOC DATE,
		MFR_NAME VARCHAR(30),
		DIRECTION_NAME VARCHAR(100),
		BUH_PRINCIPAL_NUMBER VARCHAR(255),
		AGENT_NAME VARCHAR(255),
		BUDGET_NAME VARCHAR(255),		
		DEAL_PRODUCT_NAME VARCHAR(500),
		DEAL_MFR_NUMBER VARCHAR(255),
		ARTICLE_GROUP_NAME VARCHAR(255),
		ARTICLE_NAME VARCHAR(255),
    	VALUE_IN DECIMAL(18,2),
		VALUE_CREDIT DECIMAL(18,2),
		VALUE_CREDIT_BACK DECIMAL(18,2),
		FINDOC_ID INT,
		PROJECT_ID INT,
		DEAL_ID INT,
		BUDGET_ID INT,
		ARTICLE_ID INT,
		)

	insert into #result(
		d_doc,
		subject_name, mfr_name, direction_name, 
		account_name, buh_principal_number, agent_name,
		budget_name, deal_product_name, deal_mfr_number,
		article_group_name, article_name, value_in, findoc_id, project_id, deal_id, budget_id, article_id
		)
	select 
		ff.d_doc,
		s.short_name,
		case
			when d.program_id is not null then 'ПРОЕКТЫ'
			when p.type_id != 3 then 'ПРОЕКТЫ'
			when p.type_id = 3 then isnull(d.mfr_name, '<НЕ РАЗНЕСЕНО>')
			else '<НЕ РАЗНЕСЕНО>'
		end,
		case
			when p.type_id != 3 then 'ПРОЕКТЫ'
			else coalesce(dir.short_name, dir.name, '<НЕ РАЗНЕСЕНО>')
		end,
		fa.name, d.buh_principal_number, ag.name,
		b.name, dp.name, left(dp.eMfrDocList, 255),
		a2.name,
		a.name,
		f.value,
		f.findoc_id,
		p.project_id,
		d.deal_id,
		f.budget_id,
		f.article_id
	from #resultInputs f
		join findocs ff on ff.findoc_id = f.findoc_id
			left join subjects s on s.subject_id = ff.subject_id
			left join findocs_accounts fa on fa.account_id = ff.account_id
			left join agents ag on ag.agent_id = ff.agent_id
		left join budgets b on b.budget_id = f.budget_id
			left join projects p on p.project_id = b.project_id
		left join bdr_articles a on a.article_id = f.article_id
			left join bdr_articles a2 on a2.article_id = a.parent_id
		left join deals d on d.budget_id = f.budget_id
			left join deals_products dp on dp.deal_id = d.deal_id and dp.row_id = f.deal_product_id
			left join depts dir on dir.dept_id = d.direction_id

-- value_credit
	declare @d_doc datetime = (select max(d_doc) from #resultInputs)

	update x
	set credit_type = '1.Финансировано',
		value_credit = cl.value,
		value_credit_back = iif(x.value_in < cl.value, x.value_in, cl.value)
	from #result x
		join deals_credits_lefts cl on cl.subject_id = @principal_id 
			and cl.d_doc = @d_doc
			and cl.budget_id = x.budget_id
			and cl.article_id = x.article_id

-- final
	select * from #result
	drop table #resultInputs, #result
end
go
