if object_id('finance_reps_inputs_buh') is not null drop proc finance_reps_inputs_buh
go
-- exec finance_reps_inputs_buh 700, 14402
create proc finance_reps_inputs_buh
	@mol_id int,
	@folder_id int,
	@trace bit = 0
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- access
		declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
		-- @subjects
		declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
		-- @budgets
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

	create table #result(
		row_id int identity primary key,
		account_name varchar(500),
		project_type varchar(500),
		d_doc datetime,
		findoc_id int index ix_findoc,
		deal_id int index ix_deal,
		project_id int,
		budget_id int,
		article_id int,
		buh_principal_number varchar(100),
		buh_principal_spec_number varchar(100),
		deal_number varchar(500),
		dogovor_number varchar(250),
		spec_number varchar(250),
		spec_date datetime,
		vendor_name varchar(500),
		agent_name varchar(500),
		mol_name varchar(500) default '',
		pay_note varchar(500),
		product_name varchar(500) default '',
    	findoc_value_rur decimal(18,2),
		value_pay decimal(18,2),
		value_pay_float float,
		value_nds decimal(18,2),
		value_contract decimal(18,2),
		value_transfer decimal(18,2),
		is_last bit
		)

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'fd'

	-- учёт проектов
		insert into #result(
			project_type, account_name, deal_number, d_doc,
			buh_principal_number, vendor_name, dogovor_number, spec_number,
			agent_name, mol_name, pay_note,
			findoc_value_rur, value_pay, value_pay_float,
			findoc_id, project_id, budget_id, article_id
			)
		select 
			p.name, fa.name, b.name,
			f.d_doc,
			isnull(docs.number, ''),
			isnull(v.short_name, ''),		
			pc.dogovor_number,
			pc.spec_number,
			a.name,
			m.name,
			ff.note,
			f.value_rur, f.value_rur, f.value_rur,
			f.findoc_id, p.project_id, f.budget_id, f.article_id
		from findocs# f		
			join @ids i on i.id = f.findoc_id
			join @subjects s on s.id = f.subject_id
			join findocs ff with(nolock) on ff.findoc_id = f.findoc_id
			join findocs_accounts fa with(nolock) on fa.account_id = f.account_id
			join budgets b with(nolock) on b.budget_id = f.budget_id
				join projects p with(nolock) on p.project_id = b.project_id and isnull(p.type_id, 1) not in (3) -- кроме сделок
					left join projects_contracts pc on pc.project_id = p.project_id
						left join documents docs on docs.document_id = pc.principal_id
						join subjects v on v.subject_id = pc.vendor_id
					join mols m on m.mol_id = p.chief_id
			join agents a on a.agent_id = f.agent_id

	-- учёт сделок
		insert into #result(
			project_type, account_name, d_doc, findoc_id, deal_id, budget_id, article_id,
			buh_principal_number, buh_principal_spec_number, deal_number, dogovor_number,
			spec_number, spec_date,
			vendor_name, agent_name, mol_name, pay_note, product_name,
			findoc_value_rur, value_pay_float, value_nds, value_contract, value_transfer
			)
		select 
			isnull(p.name, 'тек.деятельность'),
			f.account_name,
			f.d_doc, f.findoc_id, d.deal_id, f.budget_id, f.article_id,
			isnull(d.buh_principal_number, '-'),
			isnull(d.buh_principal_spec_number, '-'),
			isnull(d.number, '-'),
			d.dogovor_number, d.spec_number, d.spec_date,
			sv.short_name, a.name, m.name, f.note, dp.name,
			f.value_rur,
			case
				when d.deal_id is not null then f.value_rur * cast(dp.value_bds / nullif(d.value_ccy,0) as float)
				else f.value_rur
			end,
			dp.value_nds * f.pay_ratio,
			dp.value_bdr * f.pay_ratio,
			dp.value_transfer_pure * f.pay_ratio
		from (
			select 
				fa.name as account_name, f.d_doc, f.findoc_id, deal_id, f.budget_id, f.article_id, f.agent_id, ff.note,
				f.value_rur,
				f.value_rur/nullif(deals.value_ccy,0) as pay_ratio
			from findocs# f with(nolock)
				join @ids i on i.id = f.findoc_id
				join @subjects s on s.id = f.subject_id
				join findocs ff with(nolock) on ff.findoc_id = f.findoc_id
				join findocs_accounts fa with(nolock) on fa.account_id = f.account_id
				join deals with(nolock) on deals.budget_id = f.budget_id
			) f
			join deals d with(nolock) on d.deal_id = f.deal_id
				left join deals_products dp with(nolock) on dp.deal_id = d.deal_id			
				left join subjects sv on sv.subject_id = d.vendor_id
				left join mols m on m.mol_id = d.manager_id
				left join projects p with(nolock) on p.project_id = d.program_id
			left join agents a on a.agent_id = f.agent_id

		update #result set value_pay = isnull(value_pay_float, value_pay)

	-- обработка точности округления
		select * into #diff from (
			select findoc_id, value_rur_diff = sum(value_pay_float) - sum(value_pay) from #result group by findoc_id
			) f
		where abs(value_rur_diff) > 0

		update x
		set is_last = case when l.next_id is null then 1 end
		from #result x
				join (
					select 
						row_id,
						next_id = lead(row_id, 1, null) over (partition by findoc_id order by row_id)
					from #result
				) l on l.row_id = x.row_id

		-- копеечную разницу относим на последнюю запись
			update x
			set value_pay = x.value_pay + d.value_rur_diff
			from #result x
				join #diff d on d.findoc_id = x.findoc_id and x.is_last = 1

	-- прочее
		insert into #result(
			project_type, account_name, d_doc, findoc_id, budget_id, article_id, agent_name, pay_note, value_pay
			)
		select 
			'тек.деятельность', f.account_name, f.d_doc, f.findoc_id, f.budget_id, f.article_id, a.name, f.note, f.value_rur
		from (
			select 
				fa.name as account_name, f.d_doc, f.findoc_id, f.budget_id, f.article_id, f.agent_id, ff.note, f.value_rur
			from findocs# f
				join @ids i on i.id = f.findoc_id
				join @subjects s on s.id = f.subject_id
				join findocs ff with(nolock) on ff.findoc_id = f.findoc_id
				join findocs_accounts fa with(nolock) on fa.account_id = f.account_id
				join budgets b with(nolock) on b.budget_id = f.budget_id
			) f
			left join agents a on a.agent_id = f.agent_id
		where not exists(select 1 from #result where findoc_id = f.findoc_id and budget_id = f.budget_id and article_id = f.article_id)

	IF @TRACE = 1
		SELECT
			'КОНТРОЛЬНАЯ СУММА',
			(SELECT SUM(VALUE_RUR) FROM FINDOCS# WHERE FINDOC_ID IN (SELECT ID FROM @IDS))	
			-
			(SELECT SUM(VALUE_PAY) FROM #RESULT)

	-- final
		select * from #result

		drop table #result, #diff
end
go
