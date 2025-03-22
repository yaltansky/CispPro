if object_id('mfr_plan_qjobs_calc') is not null drop proc mfr_plan_qjobs_calc
go
-- exec mfr_plan_qjobs_calc 1508
create proc mfr_plan_qjobs_calc
	@dispatcher_id int = null,	
	@details app_pkids readonly,
	@queue_id uniqueidentifier = null 
as
begin
    set nocount on;

	create table #qjobs_details(id int primary key)
		if @queue_id is not null
			insert into #qjobs_details select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'mco'
		else
			insert into #qjobs_details select id from @details

	declare @filter_details as bit = case when exists(select 1 from #qjobs_details) then 1 end

    -- -- norm_duration, norm_duration_wk
    --     if @filter_details is null
    --     begin
    --         declare @norm_duration_wk float
    --         update x set 
    --             @norm_duration_wk = x.plan_q * (do.duration_wk * dur2.factor) / dur2h.factor,
    --             norm_duration = (do.duration * dur1.factor) / dur1d.factor,
    --             norm_duration_wk = @norm_duration_wk,
    --             plan_duration_wk = @norm_duration_wk,
    --             plan_duration_wk_id = 2
    --         from mfr_plans_jobs_details x
    --             join mfr_plans_jobs_queues q on q.detail_id = x.id
    --             join sdocs_mfr_contents c on c.content_id = x.content_id
    --                 join mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = x.oper_number
    --                     left join projects_durations dur1 on dur1.duration_id = do.duration_id
    --                     left join projects_durations dur2 on dur2.duration_id = do.duration_wk_id
    --                     join projects_durations dur1d on dur1d.duration_id = 3
    --                     join projects_durations dur2h on dur2h.duration_id = 2
    --         where isnull(x.norm_duration_wk,0) = 0
    --     end
                    
    BEGIN TRY
    BEGIN TRANSACTION
        -- delete
            delete from mfr_plans_jobs_queues
            where (@dispatcher_id is null or place_id in (select place_id from mfr_places_mols where mol_id = @dispatcher_id))
                and (@filter_details is null or detail_id in (select id from #qjobs_details))
        -- insert
            insert into mfr_plans_jobs_queues(
                detail_id, subject_id, flow_id, place_id, plan_job_id, mfr_doc_id, mfr_number, priority_id, priority_sort, priority_css, content_id, item_id, draft_id,
                oper_id, oper_number, oper_name,
                oper_status_id, oper_d_from, oper_d_to, work_type_id, plan_q, fact_q, resource_id,
                norm_hours, plan_hours, fact_hours, queue_hours,
                overloads_duration_wk, count_executors, executors_names
                )
            select
                id, subject_id, flow_id, place_id, plan_job_id, mfr_doc_id, mfr_number, priority_id, priority_sort, priority_css, content_id, item_id, draft_id,
                oper_id, oper_number, concat('#', oper_number,'-', oper_name),
                oper_status_id, oper_d_from, oper_d_to, work_type_id, plan_q, fact_q, resource_id,
                norm_hours, isnull(plan_hours,0), isnull(fact_hours,0), queue_hours,
                overloads_duration_wk, count_executors, executors_names
            from v_mfr_plans_qjobs1 x
            where (@dispatcher_id is null or place_id in (select place_id from mfr_places_mols where mol_id = @dispatcher_id))
                and (@filter_details is null or id in (select id from #qjobs_details));

        -- update
            -- adjust norm_hours, plan_hours with left_q = plan_q - fact_q
            update x set
                norm_hours = norm_hours * (plan_q - isnull(fact_q,0)) / nullif(plan_q, 0),
                plan_hours = plan_hours * (plan_q - isnull(fact_q,0)) / nullif(plan_q, 0)
            from mfr_plans_jobs_queues x
            where (@filter_details is null or x.detail_id in (select id from #qjobs_details))
                and (@dispatcher_id is null or x.place_id in (select place_id from mfr_places_mols where mol_id = @dispatcher_id));

            -- other columns
            update x set
                flow_name = f.name,
                place_code = pl.name,
                place_name = pl.note,
                job_number = j.number,
                moderator_id = j.add_mol_id,
                executor_id = j.executor_id,
                product_name = p2.name,
                parent_item_name = p1.name,
                item_type_id = c.item_type_id,
                item_type_name = it.name,
                item_name = p3.name,
                oper_d_from = isnull(x.oper_d_from, j.d_doc),
                oper_d_to = isnull(x.oper_d_to, j.d_doc),
                oper_d_from_plan = isnull(c.opers_from_plan, j.d_doc),
                oper_d_to_plan = isnull(c.opers_to_plan, j.d_doc),
                resource_name = rs.name
            from mfr_plans_jobs_queues x
                join mfr_plans_jobs j with(nolock) on j.plan_job_id = x.plan_job_id
                join mfr_plans_jobs_details jd with(nolock) on jd.id = x.detail_id	
                    left join products p1 with(nolock) on p1.product_id = jd.parent_item_id
                join products p3 with(nolock) on p3.product_id = x.item_id
                join mfr_places pl with(nolock) on pl.place_id = x.place_id
                left join sdocs_mfr_contents c with(nolock) on c.content_id = x.content_id
                    left join mfr_items_types it on it.type_id = c.item_type_id
                    left join products p2 with(nolock) on p2.product_id = c.product_id
                left join mfr_plans_jobs_flows f on f.flow_id = x.flow_id
                left join mfr_resources rs on rs.resource_id = x.resource_id
            where (@filter_details is null or x.detail_id in (select id from #qjobs_details))
                and (@dispatcher_id is null or x.place_id in (select place_id from mfr_places_mols where mol_id = @dispatcher_id))

            update x set 
                rate_price = e.rate_price
            from mfr_plans_jobs_queues x
                join mfr_drafts_opers o with(nolock) on o.draft_id = x.draft_id and o.number = x.oper_number
                    join (
                        select oper_id, rate_price = max(rate_price)
                        from mfr_drafts_opers_executors with(nolock)
                        group by oper_id
                    ) e on e.oper_id = o.oper_id
            where (@filter_details is null or x.detail_id in (select id from #qjobs_details))
                and (@dispatcher_id is null or x.place_id in (select place_id from mfr_places_mols where mol_id = @dispatcher_id))
        -- set status_id
            update mfr_plans_jobs_queues set 
                status_id = case
                        when fact_q > 0 then 1 -- в работе
                        when executors_names is not null then -2 -- есть назначения
                        when fact_q = plan_q then 100 -- сделано
                        else 0
                    end
            where (@filter_details is null or detail_id in (select id from #qjobs_details))
        -- set status_id (Готов к выдаче)
            update x set status_id = 2
            from mfr_plans_jobs_queues x
                join sdocs_mfr_opers o on o.oper_id = x.oper_id
                    join sdocs_mfr_opers prev on prev.oper_id = o.prev_id
            where (@filter_details is null or x.detail_id in (select id from #qjobs_details))
                and x.status_id = 0
                and prev.status_id = 100

            update x set status_id = 2
            from mfr_plans_jobs_queues x
                join sdocs_mfr_opers o on o.oper_id = x.oper_id
            where x.status_id = 0 and o.is_first = 1
        
        -- -- overloads_duration_wk
        --     if @dispatcher_id is not null
        --     begin
        --         declare @details2 as app_pkids
        --             insert into @details2
        --             select distinct detail_id
        --             from mfr_plans_jobs_queues
        --             where (@dispatcher_id is null or place_id in (select place_id from mfr_places_mols where mol_id = @dispatcher_id))

        --         update x set 
        --             overloads_duration_wk = case when xx.plan_hours > 60 then x.plan_duration_wk end
        --         from mfr_plans_jobs_executors x
        --             join (
        --                 select
        --                     x.id,
        --                     plan_hours = sum(x.plan_duration_wk) over (partition by x.mol_id order by q.oper_d_from, q.detail_id, x.d_doc)
        --                 from mfr_plans_jobs_executors x
        --                     join mfr_plans_jobs_queues q on q.detail_id = x.detail_id
        --                     join @details2 d on d.id = x.detail_id
        --                 ) xx on xx.id = x.id

        --         update x set
        --             overloads_duration_wk = xx.overloads_duration_wk
        --         from mfr_plans_jobs_details x
        --             join @details2 d on d.id = x.id
        --             join (
        --                 select detail_id, overloads_duration_wk = sum(overloads_duration_wk)
        --                 from mfr_plans_jobs_executors e
        --                 group by detail_id
        --             ) xx on xx.detail_id = x.id
        --     end
        --     drop table #qjobs_details
    COMMIT TRANSACTION
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        DECLARE @ERR VARCHAR(MAX) = ERROR_MESSAGE()
        RAISERROR (@ERR, 16, 1)
    END CATCH
end
go
