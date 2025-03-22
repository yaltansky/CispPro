if object_id('mfr_print_items_ms') is not null drop proc mfr_print_items_ms
go
-- exec mfr_print_items_ms 700, @plan_id = 0
-- exec mfr_print_items_ms 700, @plan_id = 7
-- exec mfr_print_items_ms 700, @folder_id = 19600
create proc mfr_print_items_ms
	@mol_id int,
	@plan_id int = null,
	@folder_id int = null, -- папка планов
	@d_doc datetime = null
as
begin

	set nocount on;

-- @params
	declare @plans as app_pkids

	if @folder_id is not null set @plan_id = null

	if @plan_id = 0 insert into @plans select plan_id from mfr_plans where status_id = 1
	else if @plan_id is not null insert into @plans select @plan_id
	else insert into @plans exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'

	set @d_doc = isnull(@d_doc, dbo.today())
	declare @d_from datetime = dateadd(d, -datepart(d, @d_doc)+1, @d_doc)
	declare @d_to datetime = dateadd(m, 1, @d_from) - 1

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @subject_id int = (select subject_id from mfr_plans where plan_id = @plan_id)
	declare @is_commerce bit = case when dbo.isinrole_byobjs(@mol_id, 'Mfr.Commerce', 'SBJ', @subject_id) = 1 then 1 end

	declare @milestones table(
		mfr_doc_id int index ix_doc,
		product_id int,
		milestone_name varchar(150),
		milestone_status varchar(250),
		milestone_value_work decimal(18,2),
		d_to date,
		d_to_plan date,
		d_to_predict date,
		d_to_fact date,
		plan_q float,
		fact_q float,
		complect_plan_q float,
		complect_fact_q float,
		primary key (mfr_doc_id, product_id, milestone_name)
		)
	
	insert into @milestones(
		mfr_doc_id, product_id, milestone_name, milestone_status, milestone_value_work, d_to, d_to_plan, d_to_predict, d_to_fact, plan_q, fact_q, complect_plan_q, complect_fact_q
		)
	exec mfr_print_items_ms;2 
		@mol_id = @mol_id,
		@plans = @plans,		
		@d_doc = @d_doc

	select *,
		DateSort = cast(null as datetime)
	into #result
	from (
		select				
			RowId = row_number() over (order by sd.number, x.milestone_name),
			MfrDocId = sd.doc_id,
			MfrNumber = sd.number,
			AgentName = a.name,
			ProductName =  p.name,
			DateOpened = sd.d_doc,
			DateDelivery = sd.d_delivery,
			TotalGroupName = isnull(g1.name, 'undefined'),
			Group1Name = isnull(g1.name, 'undefined'),
			Group2Name = sd.number,
			Group3Name = x.milestone_name,
			Group3Status = x.milestone_status,
			PeriodFrom = @d_from,
			PeriodTo = @d_to,			
			DateTo = x.d_to,
			DateToFact = case when x.plan_q <= x.fact_q then x.d_to_fact end,
			PlanQ = complect_plan_q,
			FactQ = complect_fact_q,
			OpersPlanQ = x.plan_q,
			OpersFactQ = x.fact_q,
			ValueWorkPlan = case when @is_commerce = 1 then x.milestone_value_work end,
			ValueWorkFact = case when @is_commerce = 1 and x.plan_q <= x.fact_q then x.milestone_value_work end
		from @milestones x
			join sdocs sd on sd.doc_id = x.mfr_doc_id
				left join agents a on a.agent_id = sd.agent_id
				join sdocs_products sp on sp.doc_id = sd.doc_id and sp.product_id = x.product_id
			join products p on p.product_id = x.product_id
			left join mfr_products_grp1 g1 on g1.product_id = x.product_id
		where (
			-- Факт(до) в периоде и <= заданной даты
			x.d_to_fact between @d_from and @d_to and x.d_to_fact <= @d_doc
			-- или (План(до) <= До и (Факт >= От или Пусто))
			or (x.d_to <= @d_to and isnull(x.d_to_fact, @d_from) >= @d_from)
			)
		) t

	update x 
	set DateSort = DateDelivery
	from #result x

	select * from #result
	drop table #result
end
GO
-- helper: build milestones
create proc mfr_print_items_ms;2
	@mol_id int,
	@plans as app_pkids readonly,
	@d_doc datetime = null
as
begin

	declare @milestones table(
		mfr_doc_id int index ix_doc,
		product_id int,
		milestone_name varchar(250),
		milestone_status varchar(250),
		milestone_value_work decimal(18,2),
		d_to date,
		d_to_plan date,
		d_to_predict date,
		d_to_fact date,
		plan_q float,
		fact_q float,
		complect_plan_q float,
		complect_fact_q float,
		primary key (mfr_doc_id, product_id, milestone_name)
		)

	set @d_doc = isnull(@d_doc, dbo.today())
	declare @d_from datetime = dateadd(d, -datepart(d, @d_doc)+1, @d_doc)
	declare @d_to datetime = dateadd(m, 1, @d_from) - 1

	insert into @milestones(
		mfr_doc_id, product_id, milestone_name, milestone_status, milestone_value_work,
		d_to, d_to_plan, d_to_predict, d_to_fact, plan_q, fact_q
		)
	select
		mfr_doc_id, product_id, milestone_name, milestone_status, milestone_value_work, 
		max(d_to),
		max(d_to_plan),
		max(d_to_predict),
		max(d_to_fact),
		sum(plan_q),
		sum(fact_q)
	from (
		select 
			c.mfr_doc_id,
			c.product_id,
			milestone_name = a.name,
			milestone_status = left(ms.note, 250),
			milestone_value_work = ms.ratio_value,
			d_to = isnull(max(ms.d_to), @d_from),
			d_to_plan = isnull(max(ms.d_to_plan), @d_from),
			d_to_predict = isnull(max(ms.d_to_predict), @d_from),
			d_to_fact = max(ms.d_to_fact),
			plan_q = sum(o.plan_q),
			fact_q = sum(o.fact_q)
		from sdocs_mfr_opers o
			join sdocs_mfr_contents c on c.content_id = o.content_id
				join sdocs_mfr_milestones ms on ms.doc_id = c.mfr_doc_id and ms.product_id = c.product_id and ms.attr_id = o.milestone_id
					join mfr_attrs a on a.attr_id = ms.attr_id
		where c.is_deleted = 0
			and c.plan_id in (select id from @plans)
		group by c.mfr_doc_id, c.product_id, a.name, ms.note, ms.ratio_value
		) u
	group by mfr_doc_id, product_id, milestone_name, milestone_status, milestone_value_work

	update @milestones set d_to_fact = null where fact_q < plan_q

	update @milestones set 
		complect_plan_q = cast(1 as float),
		complect_fact_q = cast(case when plan_q <= fact_q then 1 end as float)

	select * from @milestones
end
go
