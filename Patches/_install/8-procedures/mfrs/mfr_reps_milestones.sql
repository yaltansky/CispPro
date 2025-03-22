if object_id('mfr_reps_milestones') is not null drop proc mfr_reps_milestones
go
-- exec mfr_reps_milestones 700, @plan_id = 6
create proc mfr_reps_milestones
	@mol_id int,
	@plan_id int = null,
	@folder_id int = null -- папка планов
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- @plans, @docs
	declare @plans as app_pkids, @docs as app_pkids

	if @folder_id is not null set @plan_id = null

	if @plan_id = 0 insert into @plans select plan_id from mfr_plans where status_id = 1
	else if @plan_id is not null insert into @plans select @plan_id
	else begin
		insert into @plans exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'
		if not exists(select 1 from @plans)
			insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
	end

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

	declare @milestones table(
		mfr_doc_id int index ix_doc,
		product_id int,
		milestone_name varchar(150),
		milestone_value_work decimal(18,2),
		date_plan date,
		date_plan_pdo date,
		date_predict date,
		date_fact date,		
		primary key (mfr_doc_id, product_id, milestone_name)
		)

	insert into @milestones(
		mfr_doc_id, product_id, milestone_name, milestone_value_work, date_plan, date_predict, date_plan_pdo, date_fact
		)
	select 
		mfr.doc_id,
		sp.product_id,
		a.name,
		ms.ratio_value,
		ms.d_to,
		ms.d_to_predict,
		ms.d_to_plan,
		ms.d_to_fact
	from sdocs_products sp
		join mfr_sdocs mfr on mfr.doc_id = sp.doc_id
			join sdocs_mfr_milestones ms on ms.doc_id = mfr.doc_id and ms.product_id = sp.product_id
				join mfr_attrs a on a.attr_id = ms.attr_id
	where 
		(not exists(select 1 from @plans) or mfr.plan_id in (select id from @plans))
		and (not exists(select 1 from @docs) or mfr.doc_id in (select id from @docs))

	insert into @milestones(mfr_doc_id, product_id, milestone_name, date_plan, date_fact, date_plan_pdo)
	select c.mfr_doc_id, c.product_id, '[Производственный заказ]', min(sd.d_delivery_plan), max(sd.d_issue), max(sd.d_ship)
	from sdocs_mfr_contents c
		join sdocs sd on sd.doc_id = c.mfr_doc_id
	where c.is_deleted = 0
		and (not exists(select 1 from @plans) or c.plan_id in (select id from @plans))
		and (not exists(select 1 from @docs) or sd.doc_id in (select id from @docs))
	group by c.mfr_doc_id, c.product_id

	insert into @milestones(mfr_doc_id, product_id, milestone_name, date_plan, date_fact, date_plan_pdo)
	select x.doc_id, x.product_id, '[Нет состава]', min(sd.d_delivery_plan), max(sd.d_issue), max(sd.d_ship)
	from sdocs_products x
		join sdocs sd on sd.doc_id = x.doc_id
	where 
			(not exists(select 1 from @plans) or sd.plan_id in (select id from @plans))
		and (not exists(select 1 from @docs) or sd.doc_id in (select id from @docs))
		and not exists(select 1 from sdocs_mfr_contents where mfr_doc_id = sd.doc_id)
	group by x.doc_id, x.product_id

	select *,
		MilestonePlanMonth = left(convert(varchar, MilestonePlan, 20), 7),
		MilestonePredictMonth = left(convert(varchar, MilestonePredict, 20), 7),
		MilestoneFactMonth = left(convert(varchar, MilestoneFact, 20), 7),
		MilestoneDiff = datediff(d, MilestoneFact, MilestonePlan)
	from (
		select				
			RowId = row_number() over (order by sd.number, x.milestone_name),
			MfrNumber = sd.number,
			AgentName = a.name,
			DateOpened = sd.d_doc,
			DateDelivery = sd.d_delivery,
			DateIssuePlan = sd.d_issue_plan,
			DateIssueForecast = sd.d_issue_forecast,
			DateIssue = sd.d_issue,
			TotalGroupName = isnull(g1.name, 'undefined'),
			GroupName = concat('Производственный заказ №', sd.number),
			ProductName = p.name,
			MilestoneName = x.milestone_name,
			MilestoneValueWork = x.milestone_value_work,
			MilestonePlan = x.date_plan,
			MilestonePlanPDO = x.date_plan_pdo,
			MilestonePredict = x.date_predict,
			MilestoneFact = x.date_fact,
			MfrDocHID = concat('#', x.mfr_doc_id),
			ProductHID = concat('#', x.product_id)
		from @milestones x
			join sdocs sd on sd.doc_id = x.mfr_doc_id
				left join agents a on a.agent_id = sd.agent_id
			join products p on p.product_id = x.product_id
			left join mfr_products_grp1 g1 on g1.product_id = x.product_id
		) u

end
GO
