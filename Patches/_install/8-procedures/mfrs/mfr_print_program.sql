if object_id('mfr_print_program') is not null drop proc mfr_print_program
go
-- exec mfr_print_program 1000, 0
create proc mfr_print_program
	@mol_id int,
	@plan_id int,
	@version_id int = 0,
	@folder_id int = null, -- папка планов
	@d_doc datetime = null,
    @search varchar(max) = null,
    @include_forecast bit = null,
    @trace bit = 0
as
begin
	set nocount on;

    set @search = '%' + replace(@search, ' ', '%') + '%'

	if @version_id = 0 and exists(select 1 from mfr_plans_vers)
		set @version_id = (select max(version_id) from mfr_plans_vers)

    declare @ext_type_id int = 
        case
            when isnull(@include_forecast, 0) = 0 then 0
            else 1
        end

-- @plans
	declare @plans as app_pkids
	
	if @folder_id is not null set @plan_id = null

	if @plan_id = 0 insert into @plans select plan_id from mfr_plans where status_id = 1
	else if @plan_id is not null insert into @plans select @plan_id
	else insert into @plans exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'
-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

	declare @subject_id int = (select subject_id from mfr_plans where plan_id = @plan_id)
	declare @is_commerce bit = case when dbo.isinrole_byobjs(@mol_id, 'Mfr.Commerce', 'SBJ', @subject_id) = 1 then 1 end

	set @d_doc = isnull(@d_doc, dbo.today())
	declare @period_id int = dbo.date2period(@d_doc)
	declare @d_from datetime = dateadd(d, -datepart(d, @d_doc) + 1, @d_doc)
	declare @d_to datetime = dateadd(m, 1, @d_from) - 1
-- select
	declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%Готовая продукция%')

	select * into #result from (
		select
			RowId = row_number() over (order by sd.number),
			MfrNumber = sd.number,
            MfrStyle = isnull(pr.style, ''),
			AgentName = a.name,
			TotalGroupName = cast('-' as varchar(250)),
			GroupName = cast('-' as varchar(250)),
			ProductId = p.product_id,
			ProductName = p.name,
			DateOpened = cast(sd.d_doc as date),
			DateFact = x.d_fact,
			DateShipPlan = isnull(sd.d_ship, '2000-01-01'),
			DateIssuePredict = cast(coalesce(ms.d_to_predict, sd.d_issue_forecast, sd.d_ship, '2000-01-01') as date),
			DateIssuePDO = cast(coalesce(ms.d_to_plan, sd.d_issue_plan, sd.d_ship) as date),
			ValueList = cast(case when @is_commerce = 1 then sp.price_list * x.q end as decimal(18,2)),
			V = cast(case when @is_commerce = 1 then sp.value_rur * x.q / nullif(sp.quantity,0) end as decimal(18,2)),
			ValueWork = cast(sp.value_work * x.q / nullif(sp.quantity,0) as decimal(18,2)),
			Q = x.q,
			PercentMaterialsProvided = cast(null as float),
			PercentKDCompleted = cast(null as float),
            mfr_doc_id = sd.doc_id -- debug
		from (
			select mfr_doc_id, product_id, 
				d_fact = max(case when d_fact >= @d_doc then d_fact end), 
				q = sum(plan_q - isnull(case when d_fact < @d_doc then fact_q end, 0))
			from mfr_r_milestones
			where milestone_id = @attr_product
				and version_id = @version_id
			group by mfr_doc_id, product_id
			) x
			join mfr_sdocs sd with(nolock) on sd.doc_id = x.mfr_doc_id and isnull(sd.ext_type_id, @ext_type_id) = @ext_type_id
				join subjects s on s.subject_id = sd.subject_id
				left join agents a on a.agent_id = sd.agent_id
                left join mfr_ext_probabilities pr on pr.probability_id = sd.ext_probability_id
			join sdocs_products sp with(nolock) on sp.doc_id = sd.doc_id and sp.product_id = x.product_id
			left join (
				select doc_id, 
					d_to_predict = max(d_to_predict),
					d_to_plan = max(d_to_plan)
				from mfr_sdocs_milestones with(nolock)
				group by doc_id
			) ms on ms.doc_id = x.mfr_doc_id
			join products p on p.product_id = x.product_id
		where 
			-- reglament access
			sd.subject_id in (select id from @subjects)
			-- conditions
			and sd.plan_id in (select id from @plans)
			and x.q > 0
		) u
	where (isnull(DateFact, @d_doc) >= @d_from)
        and (
            @search is null or (
                u.MfrNumber like @search
                or u.AgentName like @search
                or u.ProductName like @search
                )
            )

	-- PercentKDCompleted
		update x set
            PercentKDCompleted = floor(cast(isnull(pt.progress,0) * 100 as decimal(15,4)))
		from #result x
			join sdocs sd on sd.doc_id = x.mfr_doc_id
				join projects_tasks pt on pt.task_id = sd.project_task_id

	-- PercentMaterialsProvided
		update x set
			PercentMaterialsProvided = floor(cast(ms.k_provided * 100 as decimal(15,4)))
		from #result x
			join sdocs_mfr_milestones ms on ms.doc_id = x.mfr_doc_id and ms.product_id = x.ProductId and ms.attr_id = @attr_product

    -- TotalGroupName
            declare @group_name varchar(50) = isnull(dbo.app_registry_varchar('MfrRepProgramGroup1Attr'), 'MfrTotalGrp')
            update x set TotalGroupName = g.name
            from #result x
                left join (
                    select product_id, attr_id = max(pa.attr_id) from products_attrs pa, mfr_attrs a 
                    where a.attr_id = pa.attr_id and a.group_key = @group_name group by product_id
                ) pa on pa.product_id = x.ProductId
                left join mfr_attrs g on g.attr_id = pa.attr_id
    
    -- GroupName
            set @group_name = isnull(dbo.app_registry_varchar('MfrRepProgramGroup2Attr'), 'MfrGrp')
            update x set GroupName = g.name
            from #result x
                left join (
                    select product_id, attr_id = max(pa.attr_id) from products_attrs pa, mfr_attrs a 
                    where a.attr_id = pa.attr_id and a.group_key = @group_name group by product_id
                ) pa on pa.product_id = x.ProductId
                left join mfr_attrs g on g.attr_id = pa.attr_id

    if @trace = 1 begin
        select TotalGroupName, Q, ProductName, PercentMaterialsProvided
        from #result
        where PercentMaterialsProvided >= 99.9

        return
    end

	select * from #result
	drop table #result
end
GO
