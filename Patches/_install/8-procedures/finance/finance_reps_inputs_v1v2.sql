if object_id('finance_reps_inputs_v1v2') is not null drop proc finance_reps_inputs_v1v2
go
-- exec finance_reps_inputs_v1v2 700, 26833
create proc finance_reps_inputs_v1v2
	@mol_id int,
	@folder_id int,
	@trace bit = 0
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit =
		case 
			when exists(select 1 from @budgets where id = -1) and not exists(select 1 from @budgets where id <> -1) then 1 
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
		project_id int,
		budget_id int,
		deal_product_id int,
		article_id int,
		d_doc date,
		findoc_id int,
		value decimal(18,2),
		value_nds decimal(18,2)
		)

-- учёт сделок, проектов
	exec findocs_mkdetails @mol_id = @mol_id, @folder_id = @folder_id, @leave_earlypays = 1

-- select * from findocs#
-- where findoc_id in (
-- select f.findoc_id
-- from #resultInputs x
-- 	join findocs f on f.findoc_id = x.findoc_id
-- 	join deals d on d.budget_id = x.budget_id
-- where d.deal_id = 13590)
-- goto final

-- select value_bds, value_nds from deals_budgets where deal_id = 13590
-- 	and value_bds > 0

	-- access by @subjects
	delete x from #resultInputs x
		join findocs f on f.findoc_id = x.findoc_id
	where not (
		f.subject_id in (select id from @subjects)
		)	

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'fd'

	declare @max_date datetime = (
		select max(d_doc) from findocs
		where findoc_id in (select id from @ids)
		)

-- prepare #result
	create table #result(
		MFR_NAME VARCHAR(30),
		DIRECTION_NAME VARCHAR(50),
		MOL_NAME VARCHAR(50),
		MEMBER_NAME VARCHAR(50),
		AGENT_NAME VARCHAR(250),
		DEAL_NAME VARCHAR(250),
		DEAL_CRM_NUMBER VARCHAR(50),
		ARTICLE_NAME VARCHAR(250),
		D_DOC DATETIME,
		PAY_CURRENT_TYPE VARCHAR(30),
		DEAL_CLOSE_TYPE VARCHAR(30) default '1.Открытые сделки',
        VALUE_IN DECIMAL(18,2),
		VALUE_V1 DECIMAL(18,2),
		VALUE_V1_2 DECIMAL(18,2),
		VALUE_V2 DECIMAL(18,2),
		VALUE_V2_2 DECIMAL(18,2),
		VALUE_C DECIMAL(18,2),
		VALUE_NDS DECIMAL(18,2),
		VALUE_NDS_REFUND DECIMAL(18,2),		
		KV FLOAT,
		KC FLOAT,
		NDS_RATIO FLOAT,
		ACCOUNT_ID INT,
		FINDOC_ID INT,
		PROJECT_ID INT,
		DEAL_ID INT INDEX IX_DEALS,
		ARTICLE_ID INT,
		PAY_ARTICLE_ID INT
		)

	insert into #result(
		mfr_name, direction_name,
		mol_name, member_name,
		agent_name, deal_name, deal_crm_number, article_name,
		d_doc, pay_current_type,
		value_in, value_nds, kv, kc, nds_ratio,
		account_id, findoc_id, project_id, deal_id, article_id, pay_article_id
		)
	select 
		isnull(d.mfr_name, '-'),
		coalesce(dir.short_name, dir.name, '-'),
		isnull(mols.name, chiefs.name),
		isnull(m2.name, dm.note),
		ag.name,
		coalesce(d.number, p.name, '-'),
		d.crm_number,
		a.name,
		f.d_doc,
		case 
			when x.folder_id is null then '1.Прошлые периоды'
			else '2.Текущий период'
		end,
		x.value * isnull(dm.kv, 1),
		isnull(x.value_nds,0) * isnull(dm.kv, 1),
		isnull(dm.kv, 1),
		isnull(dm.kc, 1),
		dnds.nds_ratio,
		f.account_id,
		x.findoc_id,
		x.project_id,
		d.deal_id,
		x.article_id,
		f.article_id
	from #resultInputs x
		join findocs f on f.findoc_id = x.findoc_id
			left join agents ag on ag.agent_id = f.agent_id
		join bdr_articles a on a.article_id = x.article_id
		left join deals d on d.budget_id = x.budget_id
			left join (
				select deal_id, min(nds_ratio) nds_ratio
				from deals_products
				group by deal_id
			) dnds on dnds.deal_id = d.deal_id
			left join depts dir on dir.dept_id = d.direction_id
			left join mols on mols.mol_id = d.manager_id
			left join deals_mols dm on dm.deal_id = d.deal_id
				left join mols m2 on m2.mol_id = dm.mol_id
		left join projects p on p.project_id = x.project_id
			left join mols chiefs on chiefs.mol_id = p.chief_id
	where f.d_doc <= @max_date

-- deal_close_type
	update x
	set deal_close_type = '2.Закрытые сделки'
	from #result x
		join (
			select d.deal_id
			from #result r
				join deals d on d.deal_id = r.deal_id			
			group by d.deal_id
			having max(d.value_ccy) - sum(r.value_in) <= 0.01
		) d on d.deal_id = x.deal_id

if @trace = 1
begin
	select r.*
	from #result r
		join deals d on d.deal_id = r.deal_id
	where d.number = 'эм-л20-62'
	return
end

-- value_v1
	update x
	set value_v1 = value_in - value_nds
	from #result x
	where exists(select 1 from deals_costs where deal_id = x.deal_id and article_id = x.article_id)

-- value_v2
	update x
	set value_v2 = ((value_in - value_nds) / nullif(x.kv, 0)) * x.kc
	from #result x
	where exists(
		select 1 from deals_budgets where deal_id = x.deal_id 
		and type_id = 4 -- Ценовая премия, Дополнительное вознаграждение, НДС
		and article_id = x.article_id
		)

	update x
	set value_v1_2 = value_v1 * (1 + nds_ratio),
		value_v2_2 = value_v2 * (1 + nds_ratio)
	from #result x
	where nds_ratio is not null

-- value_c
	update x
	set value_c = value_in - value_nds
	from #result x
	where exists(
		select 1 from deals_budgets where deal_id = x.deal_id 
		and type_id = 3 -- Доп. расходы
		and article_id = x.article_id
		)

-- обнуляем суммы виртуальных приходов по возмещению НДС
	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

	update x
	set value_in = 0,
		value_nds_refund = -x.value_in
	from #result x
		join findocs_accounts a on a.account_id = x.account_id
	where a.name = @vat_refund

	select * from #result

	final:	
	exec drop_temp_table '#resultInputs,#result'
end
go
-- exec finance_reps_inputs_v1v2 1000, 56449
