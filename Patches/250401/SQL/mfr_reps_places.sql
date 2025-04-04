if object_id('mfr_reps_places') is not null drop proc mfr_reps_places
go
create proc mfr_reps_places
	@mol_id int,
    @version_id int = 0,
    @folder_id int = null, -- папка заказов
    @d_from datetime = null,
    @d_to datetime = null
as
begin
	set nocount on;

	if isnull(@version_id, 0) = 0 and exists(select 1 from mfr_plans_vers)
		set @version_id = (select max(version_id) from mfr_plans_vers)

	-- #docs
		create table #docs(id int primary key)

		if @folder_id is not null
        begin
            set @folder_id = isnull(@folder_id, dbo.objs_buffer_id(@mol_id))
		    insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
        end

        else
		    insert into #docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id >= 0

	-- reglament access
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key);	insert into #subjects select distinct obj_id from @objects where obj_type = 'sbj'

	declare @d_doc date = (select d_doc from mfr_plans_vers where version_id = @version_id)
	
    if @d_from is null
        set @d_from = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)
	
    if @d_to is null
        set @d_to = dateadd(d, -1, dateadd(m, 1, @d_from))

    exec mfr_plan_rates_calc;4 @version_id = @version_id

    -- select
    select * from (
        select 
            concat(p.name, '-', p.note) as PlaceName,
            mfr.number as MfrNumber,
            concat('#', mfr.doc_id) as MfrHid,
            mfr.agent_name as AgentName,
            r.mfr_d_plan as DateIssuePlan,
            mfr.d_delivery as DateDelivery,
            g1.name as Group1Name,
            pr.name as ProductName,
            r.d_plan as DatePlan,
            cast(null as date) as DateFact,
            r.d_plan as DocDate,
            r.plan_q as QtyPlan,
            cast(null as float)  as QtyFact
        from mfr_r_places r
            join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
                join #docs d on d.id = mfr.doc_id
                join #subjects s on s.id = mfr.subject_id
            join mfr_places p on p.place_id = r.place_id
            join products pr on pr.product_id = r.product_id
            left join mfr_products_grp1 g1 on g1.product_id = r.product_id
        where r.version_id = @version_id
            and r.plan_q > 0

        union all
        select 
            concat(p.name, '-', p.note) as PlaceName,
            mfr.number as MfrNumber,
            concat('#', mfr.doc_id) as MfrHid,
            mfr.agent_name as AgentName,
            r.mfr_d_plan as DateIssuePlan,
            mfr.d_delivery as DateDelivery,
            g1.name as Group1Name,
            pr.name as ProductName, 
            null, -- DatePlan
            r.d_fact as DateFact,
            r.d_fact as DocDate,
            null, -- QtyPlan
            r.fact_q as QtyFact
        from mfr_r_places r
            join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
                join #docs d on d.id = mfr.doc_id
                join #subjects s on s.id = mfr.subject_id
            join mfr_places p on p.place_id = r.place_id
            join products pr on pr.product_id = r.product_id
            left join mfr_products_grp1 g1 on g1.product_id = r.product_id
        where r.version_id = @version_id
            and r.fact_q > 0
    ) u
    where DocDate between @d_from and @d_to
end
GO
-- exec mfr_reps_places 1000, @d_from = '2025-04-01', @d_to = '2025-04-06'