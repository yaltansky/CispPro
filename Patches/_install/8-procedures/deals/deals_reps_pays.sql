if object_id('deals_reps_pays') is not null drop proc deals_reps_pays
go
-- exec deals_reps_pays 700, 12423
create proc deals_reps_pays
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'

-- reglament access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @vendors as app_pkids; insert into @vendors select distinct obj_id from @objects where obj_type = 'vnd'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit = case when exists(select 1 from @budgets where id = -1) then 1 else 0 end

	declare @result table(
		row_id int identity primary key,
		deal_id int index ix_deal,
		budget_id int index ix_budget,
		findoc_id int index ix_findoc,
		subject_id int,
		vendor_id int,
		account_id int,		
		deal_name varchar(500),
		pay_step varchar(100),
		number varchar(100),
		d_doc datetime,
		plan_v decimal(18,2),
		fact_v decimal(18,2),
		note varchar(max)
		)

	insert into @result(
		deal_id, budget_id, subject_id, vendor_id, pay_step, d_doc, plan_v
		)
	select
		x.deal_id, x.budget_id, x.subject_id, x.vendor_id,
		dbo.deal_paystepname(db.task_name, db.date_lag, db.ratio),
		db.task_date, db.value_bds
	from deals x
		join deals_budgets db on db.deal_id = x.deal_id
		join @ids i on i.id = x.deal_id
	where db.type_id = 1
		and db.value_bds > 0

	insert into @result(
		deal_id, budget_id, findoc_id, subject_id, vendor_id, account_id, pay_step, number, d_doc, fact_v, note
		)
	select
		d.deal_id, x.budget_id, x.findoc_id, x.subject_id, d.vendor_id, x.account_id, 
		'Фактическое поступление',
		f.number, x.d_doc, x.value_rur, f.note
	from findocs# x 
		join budgets b on b.budget_id = x.budget_id
			join deals d on d.budget_id = b.budget_id
				join @ids i on i.id = d.deal_id
		join findocs f on f.findoc_id = x.findoc_id
	where x.article_id = 24

	select
		subject_name = s.short_name,
		deal_name = concat(d.number, ' ', a.name),
		period_name = dbo.date2month(x.d_doc),
		x.d_doc,
		x.pay_step,
		number = isnull(x.number, ''),
		account_name = fa.name,
		note = x.note,
		x.plan_v,
        x.fact_v,
        deal_hid = concat('#', x.deal_id),
		findoc_hid = concat('#', x.findoc_id),
		budget_hid = concat('#', x.budget_id)
	from @result x
		join subjects s on s.subject_id = x.subject_id
		join deals d on d.deal_id = x.deal_id
			join agents a on a.agent_id = d.customer_id
		left join findocs_accounts fa on fa.account_id = x.account_id
	where 
		-- reglament access
		(
		x.subject_id in (select id from @subjects)
		or x.vendor_id in (select id from @vendors)
		or (@all_budgets = 1 or x.budget_id in (select id from @budgets))
		)
end
GO
