if object_id('mfr_reps_places') is not null drop proc mfr_reps_places
go
-- exec mfr_reps_places 1000
create proc mfr_reps_places
	@mol_id int,
    @version_id int = 0,
    @folder_id int = null -- папка заказов
as
begin

	set nocount on;

	if @version_id = 0 and exists(select 1 from mfr_plans_vers)
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
	declare @d_from datetime = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)
	declare @d_to datetime = dateadd(m, 1, @d_from) - 1

    exec mfr_plan_rates_calc;4 @version_id = @version_id

    -- select
    select 
        PlaceName = concat(p.name, '-', p.note), 
        MfrNumber = mfr.number,
        MfrHid = concat('#', mfr.doc_id),
        AgentName = mfr.agent_name,
        DateIssuePlan = r.mfr_d_plan,
        DateDelivery = mfr.d_delivery,
        Group1Name = g1.name,
        ProductName = pr.name, 
        DatePlan = r.d_plan,
        DateFact = r.d_fact,
        DocDate = coalesce(r.d_fact, r.d_plan),
        QtyPlan = r.plan_q, 
        QtyFact = r.fact_q
    from mfr_r_places r
        join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
            join #docs d on d.id = mfr.doc_id
            join #subjects s on s.id = mfr.subject_id
        join mfr_places p on p.place_id = r.place_id
        join products pr on pr.product_id = r.product_id
        left join mfr_products_grp1 g1 on g1.product_id = r.product_id
    where r.version_id = @version_id
        and r.mfr_d_plan >= @d_from
end
GO
