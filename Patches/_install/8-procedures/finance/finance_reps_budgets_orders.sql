if object_id('finance_reps_budgets_orders') is not null drop proc finance_reps_budgets_orders
go
-- exec finance_reps_budgets_orders 700, 40278
create proc finance_reps_budgets_orders
	@mol_id int,
	@folder_id int
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- access
	declare @objects as app_objects;
	insert into @objects
	exec budgets_reglament @mol_id = @mol_id
	-- @allow_budgets
	declare @allow_budgets as app_pkids;
	insert into @allow_budgets
	select distinct obj_id
	from @objects
	where obj_type = 'bdg'

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

	declare @budgets as app_pkids
	insert into @budgets
	exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'BDG'

	if not exists(select 1
	from @allow_budgets
	where id = -1)
		delete x from @budgets x where not exists(select 1
	from @allow_budgets
	where id = x.id)

	-- @provides
	declare @provides table(
		id_order int,
		budget_id int,
		status_id int,
		id_mfr int,
		product_id int,
		part_status float,
		index ix1 (id_order, status_id),
		index ix2 (budget_id)
		)

	insert into @provides
		(id_order, budget_id, status_id, id_mfr, product_id, part_status)
	select o.id_order, o.budget_id, o.status_id, o.id_mfr, o.product_id,
		case isnull(o.status_id,0)
			when 0  then 1
			when 1  then 1
			when 2 then	o.q_mfr / xx.q_order
			when 3 then	o.q_issue / xx.q_order
			when 4 then	o.q_ship / xx.q_order
		end
	from ( 
		select
			x.id_order, b.budget_id, x.status_id, x.id_mfr, x.product_id,
			q_mfr = sum(x.q_mfr), q_issue = sum(x.q_issue), q_ship = sum(x.q_ship)
		from sdocs_provides x
			join sdocs sd on sd.doc_id = x.id_order
			join budgets b on b.budget_id = sd.budget_id
			join @budgets i on i.id = b.budget_id
		group by x.id_order, b.budget_id, x.status_id, x.id_mfr, x.product_id
		) o
		join (
			select id_order, q_order = sum(q_order)
		from sdocs_provides
		where q_order > 0
		group by id_order
		) xx on xx.id_order = o.id_order

	declare @result table(
		order_id int index ix_order,
		status_id int,
		mfr_id int,
		product_id int,
		budget_id int,
		budget_period_id int,
		article_group_name varchar(30),
		article_id int,
		value_plan float,
		value_fact float,
		value_fund float,
		index ix_budget (budget_id, article_id)
		)

	insert into @result
		(
		order_id, status_id, mfr_id, product_id,
		budget_id, budget_period_id, article_id,
		value_plan, value_fact
		)
	select
		isnull(pr.id_order, 0), isnull(pr.status_id, 0), isnull(pr.id_mfr, 0), isnull(pr.product_id, 0),
		bt.budget_id, bt.budget_period_id, bt.article_id,
		bt.plan_rur * isnull(pr.part_status, 1),
		bt.fact_rur * isnull(pr.part_status, 1)
	from (
		select
			budget_id, budget_period_id, article_id,
			plan_rur = sum(plan_rur),
			fact_rur = sum(fact_rur_goal)
		from budgets_plans
		where budget_id in (select id from @budgets)
			and has_childs = 0
		group by budget_id, budget_period_id, article_id
		) bt
		join budgets_periods per on per.budget_period_id = bt.budget_period_id
		left join @provides pr on pr.budget_id = bt.budget_id

	declare @fund table(
		budget_id int,
		article_id int,
		value_fund float,
		primary key (budget_id, article_id)
		)
	insert into @fund
		(budget_id, article_id, value_fund)
	select budget_id, article_id, sum(pd.value_rur)
	from payorders_details pd
		join payorders p on p.payorder_id = pd.payorder_id
		join @budgets i on i.id = pd.budget_id
	where p.type_id = 2
	group by budget_id, article_id

	update x set value_fund = xx.value_fund
	from @result x
		join @fund xx on xx.budget_id = x.budget_id and xx.article_id = x.article_id

	declare @article_incomes int = (select top 1 article_id from bdr_articles where name like '%Поступления по основным видам деятельности')

	update @result set article_group_name = 
		case
			when article_id = @article_incomes then 'Расчёты с покупателями'
			else 'Расчёты с поставщиками'
		end

	select
		order_date = sd.d_doc,
		order_number = isnull(sd.number, '-'),
		order_agent = isnull(a.name, '-'),
		order_status = concat(s.status_id, '.', s.name),
		mfr_number = isnull(mfr.number, '-'),
		product_name = isnull(p.name, '-'),
		budget_name = b.name,
		period_from = per.date_start,
		period_to = per.date_end,
		article_group_name = x.article_group_name,
		article_name = aa.name,
		x.value_plan,
		x.value_fact,
		x.value_fund,
		order_hid = concat('#', x.order_id),
		budget_hid = concat('#', x.budget_id)
	from @result x
		left join sdocs sd on sd.doc_id = x.order_id
		left join agents a on a.agent_id = sd.agent_id
		left join sdocs_mfr mfr on mfr.doc_id = x.mfr_id
		left join products p on p.product_id = x.product_id
		join sdocs_provides_statuses s on s.status_id = x.status_id
		join budgets b on b.budget_id = x.budget_id
		join budgets_periods per on per.budget_period_id = x.budget_period_id
		join bdr_articles aa on aa.article_id = x.article_id
	where 
		x.value_plan is not null or x.value_fact is not null or x.value_fund is not null

end
go
