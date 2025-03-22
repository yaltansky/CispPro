if object_id('mfr_reps_milestones_sync') is not null drop proc mfr_reps_milestones_sync
go
create proc mfr_reps_milestones_sync
	@mol_id int,
	@folder_id int = null, -- буфер/папка заказов
	@version_id int = null,
	@attr_group_id int = 306
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if nullif(@version_id,0) is null set @version_id = (select max(version_id) from mfr_plans_vers)
	
-- @plans
	declare @docs as app_pkids

	if @folder_id is null
		insert into @docs select distinct mfr_doc_id from mfr_r_planfact where version_id = @version_id
	else begin
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
	end

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

-- @milestones
	declare @milestones table(
		MFR_DOC_ID INT,
		MFR_NUMBER VARCHAR(50),
		SUBJECT_NAME VARCHAR(50),
		D_DOC DATE,
		AGENT_NAME VARCHAR(250),
		D_DELIVERY DATE,
		D_ISSUE_PLAN DATE,
		D_ISSUE_FORECAST DATE,
		PRODUCT_ID INT,
		PRODUCT_NAME VARCHAR(500),
		CONTENT_ID INT,
		ITEM_NAME VARCHAR(500),
		UNIT_NAME VARCHAR(20),
		MILESTONE_ID INT,
		MILESTONE_NAME VARCHAR(100),
		ISSUE_STATUS VARCHAR(20),		
		D_PLAN DATE,
		D_FACT DATE,
		PLAN_Q FLOAT,
		FACT_Q FLOAT,
		INDEX IX_JOIN1 (MFR_DOC_ID, MILESTONE_ID),
		INDEX IX_JOIN2 (MFR_DOC_ID, CONTENT_ID),
		INDEX IX_JOIN3 (MFR_DOC_ID, PRODUCT_ID, MILESTONE_ID)
		)

	insert into @milestones(
		mfr_doc_id, mfr_number, subject_name, d_doc, agent_name, d_delivery, d_issue_plan, d_issue_forecast,
		product_id, product_name, content_id, item_name, unit_name,
		milestone_id, milestone_name, issue_status,
		d_plan, d_fact, plan_q, fact_q
		)
	select 
		mfr_doc_id, mfr_number, subject_name, d_doc, agent_name, d_delivery, d_issue_plan, d_issue_forecast,
		product_id, product_name, content_id, item_name, unit_name,
		milestone_id, milestone_name, issue_status,
		d_plan, d_fact, plan_q, fact_q
	from v_mfr_r_milestones x
	    join @docs i on i.id = x.mfr_doc_id
	where version_id = @version_id

	declare @pgroups table(product_id int primary key, group_name varchar(255))
		insert into @pgroups(product_id, group_name)
		select a.product_id, left(concat(aa.name, '-', a.attr_value), 255)
		from products_attrs a
			join prodmeta_attrs aa on aa.attr_id = a.attr_id and aa.attr_id = @attr_group_id
        where a.product_id is not null

	select 
		MONTH_ISSUE_PLAN = left(convert(varchar(10), d_issue_plan, 20), 7)
		, WEEK_ISSUE_PLAN = concat(datepart(year, d_issue_plan), '-нед-', right('00' + cast(datepart(iso_week, d_issue_plan) as varchar), 2))
		, PRODUCT_CLASS_NAME = CLS.NAME
		, PRODUCT_GROUP_NAME = PG.GROUP_NAME
		, ms.*
	from (
		select 
			MFR_DOC_ID, MFR_NUMBER, SUBJECT_NAME, D_DOC, AGENT_NAME, D_DELIVERY, D_ISSUE_PLAN, D_ISSUE_FORECAST, PRODUCT_ID, PRODUCT_NAME, MILESTONE_NAME, ISSUE_STATUS,
			D_PLAN = max(D_PLAN),
			D_FACT = max(D_FACT), 
			PLAN_Q = min(PLAN_Q),
			FACT_Q = min(FACT_Q)
		from @milestones
		group by 
			mfr_doc_id, mfr_number, subject_name, d_doc, agent_name, d_delivery, d_issue_plan, d_issue_forecast, product_id, product_name, milestone_name, issue_status
		) ms
		left join @pgroups pg on pg.product_id = ms.product_id
		join products p on p.product_id = ms.product_id
			left join prodmeta_classes cls on cls.class_id = p.class_id
	-- where mfr_number = '22319РМ/2' and milestone_name like '%готовая продукция%'

end
GO
-- exec mfr_reps_milestones_sync 1000
