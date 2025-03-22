if object_id('mfr_reps_indicators') is not null drop proc mfr_reps_indicators
go
-- exec mfr_reps_indicators 1000, -1
create proc mfr_reps_indicators
	@mol_id int,
	@folder_id int = null,
	@d_doc datetime = null
as
begin

	set nocount on;
	set transaction isolation level read uncommitted;

	create table #contents(id int primary key)

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	if @folder_id is not null insert into #contents exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfc'
	
-- @plans
	declare @plans as app_pkids
	insert into @plans select plan_id from mfr_plans where status_id = 1

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

-- @d_from, @d_to
	declare @d_from date, @d_to date
	
	if exists(select 1 from #contents)
	begin
		if @d_doc is null
		begin
			set @d_doc = '9999-12-31'
			set @d_from = '1900-01-01'
			set @d_to = @d_doc
		end		
	end

	else
		set @d_doc = isnull(@d_doc, dbo.today())

	set @d_from = isnull(@d_from, dateadd(d, -datepart(d, @d_doc)+1, @d_doc))
	set @d_to = isnull(@d_to, dateadd(d, -1, dateadd(m, 1, @d_from)))
	
	create table #result(
		RowId int identity,
		plan_id int,
		place_id int,		
		content_id int,
		item_id int,
		MfrNumber varchar(50),
		MfrSlice varchar(50) index ix_slice,
		PlaceName varchar(250),
		ItemSlice varchar(50), -- obsolete
		ItemName varchar(500),
		ItemStatus varchar(20),
		plan_q float,
		fact_q float,
		d_plan datetime,
		d_fact datetime,
		d_closed datetime,
		PmLag int, -- отставание		
		PmLefts float, -- входящие остатки
		PmPlan float, -- план на месяц
		PmRunningPlan float, -- план нарастающим
		PmRunningFact float, -- факт нарастающим
		PmRunningFactByOverPlan float, -- факт нарастающим сверхплана
		PmRunningUndone float, -- недодел нарастающим
		PmDayPlan float, -- план за день
		PmDayFactByUndone float, -- факт за день по недоделу
		PmDayFactByPlan float, -- факт за день по плану
		PmDayFactByOverPlan float, -- факт за день сверхплана
		-- obsolete
		PmTempoPlan float, -- плановый темп
		PmQueueOver int, -- кол-во деталей в очереди (просрочено)
		PmQueue int, -- кол-во деталей в очереди (текущие)
		PmQueueDate datetime, -- дата очереди (мин. дата сменного задания)
		PmLaborHours float, -- труд нарастающим
		PmLoadingEquipments float, -- загрузка оборудования нарастающим
		PmMaxDatePlan datetime, -- дата выполнения плана
		primary key(place_id, content_id)
		)

	-- #items
		create table #items(
			plan_id int,
			mfr_doc_id int index ix_mfr_doc,
			place_id int,
			content_id int,
			status_id int,
			item_id int,
			plan_q float,
			fact_q float,
			d_plan date,
			d_fact date
			)
			;create index ix_fifo on #items(place_id, content_id)

		insert into #items(
			plan_id, mfr_doc_id, place_id, content_id, status_id, item_id, plan_q, fact_q, d_plan, d_fact		
			)
		select
			x.plan_id,
			x.mfr_doc_id,
			o.place_id,
			x.content_id,
			c.status_id,
			max(x.item_id),
			sum(x.plan_q),
			sum(case when x.job_status_id = 100 then x.fact_q end),
			min(x.oper_date),
			max(case when x.job_status_id = 100 then x.job_date end)
		from mfr_r_plans_jobs_items x
			join sdocs_mfr_opers o on o.oper_id = x.oper_id
			join mfr_sdocs_contents c on c.content_id = x.content_id
		where o.place_id is not null
			and x.plan_id in (select id from @plans)
			and (@folder_id is null or x.content_id in (select id from #contents))
		group by x.plan_id, x.mfr_doc_id, o.place_id, x.content_id, c.status_id
		
		update #items set d_fact = null where plan_q > isnull(fact_q,0) and d_fact is not null

	-- #result
	insert into #result(
		plan_id, place_id, content_id, item_id, 
		MfrNumber, MfrSlice,
		PlaceName, ItemName, ItemStatus,
		plan_q, fact_q, d_plan, d_fact
		)
	select
		plan_id, place_id, content_id, product_id,
		mfr_number, plan_number,
		place_name, item_name, item_status,
		plan_q, fact_q, d_plan, d_fact
	from (
		select 
			c.plan_id, c.place_id, c.content_id, p.product_id,
			mfr_number = sd.number,
			plan_number = pl.number,
			place_name = plc.full_name,
			item_name = p.name,
			item_status = s.name,
			c.plan_q,
			c.fact_q,
			c.d_plan,
			c.d_fact
		from #items c
			join sdocs sd on sd.doc_id = c.mfr_doc_id
			join mfr_plans pl on pl.plan_id = c.plan_id
			join mfr_places plc on plc.place_id = c.place_id
			join products p on p.product_id = c.item_id
			left join mfr_items_statuses s on s.status_id = c.status_id
	) o
	where (
		-- Факт(до) в периоде и <= заданной даты
		d_fact between @d_from and @d_to and d_fact <= @d_doc
		-- или (План(до) <= До и (Факт >= От или Пусто))
		or (d_plan <= @d_to and isnull(d_fact, @d_from) >= @d_from)
		)

	drop table #items

	declare @wk_days int = dbo.work_day_diff(@d_from, @d_to)

-- оставание
	update #result set PmLag = datediff(d, d_plan, @d_doc) where d_fact is null and d_plan <= @d_doc

-- входящие остатки
	update #result set PmLefts = fact_q where d_fact < @d_from

-- план на месяц
	update #result set PmPlan = plan_q where d_plan <= @d_to and isnull(d_fact, @d_from) >= @d_from

-- план нарастающим
	update #result set PmRunningPlan = plan_q where d_plan <= @d_doc and isnull(d_fact, @d_from) >= @d_from

-- факт нарастающим
	update #result set PmRunningFact = fact_q where fact_q > 0

-- факт нарастающим сверхплана
	update #result set PmRunningFactByOverPlan = fact_q where d_plan > @d_doc and fact_q > 0

-- недодел, план, факт
	declare @undone float
	
	update #result set 
		@undone = 
			case 
				when d_plan < @d_doc then plan_q - isnull(fact_q,0)
			end,

		PmRunningUndone = case when @undone > 0 then @undone end,

		PmDayPlan =
			case	
				when d_plan = @d_doc then plan_q
			end,

		PmDayFactByUndone =
			case
				when d_fact = @d_doc and d_plan < @d_doc then fact_q
			end,

		PmDayFactByPlan =
			case
				when d_fact = @d_doc and d_plan = @d_doc then fact_q
			end,

		PmDayFactByOverPlan =
			case
				when d_fact = @d_doc and isnull(d_plan, @d_doc + 1) > @d_doc then fact_q
			end

	select *,
		PmDatePlan = d_plan,
		PmDateFact = d_fact,
		ContentHid = concat('#', content_id)
	from #result

	exec drop_temp_table '#contents,#items,#result'
end
GO
