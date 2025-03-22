if object_id('mfr_docs_infos_calc') is not null drop proc mfr_docs_infos_calc
go
create proc mfr_docs_infos_calc
	@mol_id int,
	@doc_id int = null,
    @info_id int = null out,
    @trace bit = 0
as
begin
	set nocount on;

    declare @today date = dbo.today()

    if @trace = 1
        delete from mfr_docs_infos where mfr_doc_id = @doc_id

    -- @infos
        declare @infos app_pkids
            if @info_id is null begin
                insert into mfr_docs_infos(mfr_doc_id, add_mol_id)
                output inserted.info_id into @infos
                select doc_id, @mol_id from mfr_sdocs where doc_id = @doc_id
                set @info_id = (select top 1 id from @infos)
            end
            else
                insert into @infos select @info_id

    -- is_last
        update x set is_last = 0
        from mfr_docs_infos x
            join (
                select distinct mfr_doc_id
                from mfr_docs_infos x
                    join @infos i on i.id = x.info_id
            ) xx on xx.mfr_doc_id = x.mfr_doc_id
        where is_last = 1

        update x set is_last = 1
        from mfr_docs_infos x
            join @infos i on i.id = x.info_id

    -- Общие показатели:
        -- Плановый объём (PV)
            update x set mx_pv = xx.value_work
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                left join (
                    select doc_id, value_work = sum(value_work)
                    from sdocs_products
                    group by doc_id
                ) xx on xx.doc_id = x.mfr_doc_id

        -- Общая трудоёмкость, ч
            update x set 
                mx_wk_hours = xx.wk_hours,
                prod_d_from_plan = xx.d_from_plan,
                prod_d_to_plan = xx.d_to_plan
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                left join (
                    select o.mfr_doc_id, wk_hours = sum(o.duration_wk * dur.factor / dur_h.factor),
                        d_from_plan = min(o.d_from_plan),
                        d_to_plan = max(o.d_to_plan),
                        d_to_fact = max(d_to_fact)
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 0
                        join projects_durations dur on dur.duration_id = o.duration_wk_id
                        join projects_durations dur_h on dur_h.duration_id = 2
                    group by o.mfr_doc_id
                ) xx on xx.mfr_doc_id = x.mfr_doc_id

            update x set 
                prod_d_to_fact = mfr.d_issue
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join mfr_sdocs mfr on mfr.DOC_ID = x.MFR_DOC_ID

        -- Стоимость часа, руб/ч = Стоимость услуг / Общая трудоёмкость
            update x set mx_wk_cost = mx_pv / nullif(mx_wk_hours, 0)
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id

        -- Освоенный объём (EV): Трудоёмкость по завершённым операциям x Стоимость часа
            update x set mx_ev = xx.wk_hours * x.mx_wk_cost
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                left join (
                    select mfr_doc_id, wk_hours = sum(o.duration_wk * dur.factor / dur_h.factor)
                    from sdocs_mfr_opers o
                        join projects_durations dur on dur.duration_id = o.duration_wk_id
                        join projects_durations dur_h on dur_h.duration_id = 2
                    where o.status_id = 100
                    group by mfr_doc_id
                ) xx on xx.mfr_doc_id = x.mfr_doc_id
        
        -- Индекс выполнения плана (EV / PV)
            update x set mx_spi = mx_ev / nullif(mx_pv, 0)
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id

    -- Обеспечения материалами:
        declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%готовая продукция%')

        -- Обеспечение, %
            update x set 
                mat_k_provided = m.k_provided
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select inf.info_id, inf.mfr_doc_id, k_provided
                    from sdocs_mfr_milestones ms
                        join mfr_docs_infos inf on inf.mfr_doc_id = ms.doc_id
                            join @infos i on i.id = inf.info_id
                    where attr_id = @attr_product
                ) m on m.mfr_doc_id = x.mfr_doc_id

        -- От, до (ПДО)
            update x set 
                mat_d_from_plan = c.d_from_plan,
                mat_d_to_plan = c.d_to_plan
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select mfr_doc_id, d_from_plan = min(opers_from_plan), d_to_plan = max(opers_to_plan)
                    from sdocs_mfr_contents
                    where is_buy = 1
                    group by mfr_doc_id
                ) c on c.mfr_doc_id = x.mfr_doc_id

        -- До ПДО (факт)
            update x set 
                mat_d_to_fact = case when mat_k_provided >= 0.999 then o.d_to_fact end
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select o.mfr_doc_id, d_to_fact = max(d_to_fact)
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 1
                    group by o.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id

        -- Отставание, дн
            update x set 
                mat_delays = o.diff
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select o.mfr_doc_id, diff = max(datediff(d, o.d_to_plan, o.d_to_fact))
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 1
                    where o.status_id = 100
                    group by o.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id

        -- Текущее отставание, дн
            update x set 
                mat_delays_current = datediff(d, o.d_to_plan, @today)
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select o.mfr_doc_id, d_to_plan = min(d_to_plan)
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 1
                    where o.status_id != 100
                    group by o.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id

        -- Максимальный срок закупки, дн
            update x set 
                mat_duration = o.d_diff
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select o.mfr_doc_id, d_diff = max(datediff(d, d_from_plan, d_to_plan))
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 1
                    group by o.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id

        -- Критические материалы (по срокам готовности): первые 10 из самых ранних на критическом пути
            delete x from mfr_docs_infos_materials x
                join @infos i on i.id = x.info_id

            insert into mfr_docs_infos_materials(info_id, mfr_doc_id, slice, item_id, duration, d_to_plan, d_to_fact)
            select info_id, mfr_doc_id, 'dates', item_id, duration, opers_to_plan, opers_to_fact
            from (
                select m.info_id, m.mfr_doc_id, m.item_id,
                    m.duration, m.opers_to_plan, m.opers_to_fact,
                    c_index = row_number() over (partition by mfr_doc_id order by opers_to_plan)
                from (
                    select inf.info_id, inf.mfr_doc_id, c.item_id, 
                        duration = max(datediff(d, opers_from_plan, opers_to_plan)),
                        opers_to_plan = min(opers_to_plan),
                        opers_to_fact = max(opers_to_fact)
                    from sdocs_mfr_contents c
                        join mfr_docs_infos inf on inf.mfr_doc_id = c.mfr_doc_id
                            join @infos i on i.id = inf.info_id
                    where is_buy = 1
                        and duration_buffer = 0
                    group by inf.info_id, inf.mfr_doc_id, c.item_id
                    ) m
                ) oo
            where oo.c_index <= 10

        -- Критические материалы (по срокам закупки): первые 10 из самых длинных сроков закупки
            insert into mfr_docs_infos_materials(info_id, mfr_doc_id, slice, item_id, duration, d_to_plan, d_to_fact)
            select info_id, mfr_doc_id, 'duration', item_id, duration, opers_to_plan, opers_to_fact
            from (
                select m.info_id, m.mfr_doc_id, m.item_id,
                    m.duration, m.opers_to_plan, m.opers_to_fact,
                    c_index = row_number() over (partition by mfr_doc_id order by duration desc)
                from (
                    select inf.info_id, inf.mfr_doc_id, c.item_id, 
                        duration = max(datediff(d, opers_from_plan, opers_to_plan)),
                        opers_to_plan = min(opers_to_plan),
                        opers_to_fact = max(opers_to_fact)
                    from sdocs_mfr_contents c
                        join mfr_docs_infos inf on inf.mfr_doc_id = c.mfr_doc_id
                            join @infos i on i.id = inf.info_id
                    where is_buy = 1
                    group by inf.info_id, inf.mfr_doc_id, c.item_id
                    ) m
                ) oo
            where oo.c_index <= 10

    -- Сроки производства:
        -- Длительность цикла, дн
            update x set prod_duration = datediff(d, xx.d_from_plan, xx.d_to_plan)
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                left join (
                    select mfr_doc_id, d_from_plan = min(opers_from_plan), d_to_plan = max(opers_to_plan)
                    from sdocs_mfr_contents
                    where is_buy = 0
                    group by mfr_doc_id
                ) xx on xx.mfr_doc_id = x.mfr_doc_id

        -- Исполнение, % (по освоенной трудоёмкости)
            update x set prod_k_completed = mx_spi
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id

        -- Отставание, дн
            update x set 
                prod_delays = datediff(d, o.d_to_plan, @today)
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select o.mfr_doc_id, d_to_plan = min(d_to_plan)
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 0
                    where o.status_id != 100
                    group by o.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id        

    -- Состояния заказа:
        delete x from mfr_docs_infos_states x
            join @infos i on i.id = x.info_id

        -- Размещение заказа (фактическая дата)
            insert into mfr_docs_infos_states(info_id, mfr_doc_id, state_id, name, d_plan, d_fact)
            select inf.info_id, inf.mfr_doc_id, st.state_id, st.name, mfr.add_date, mfr.add_date
            from mfr_sdocs mfr
                join mfr_docs_infos inf on inf.mfr_doc_id = mfr.doc_id
                    join @infos i on i.id = inf.info_id
                join mfr_docs_infos_states_refs st on st.state_id = 1

        -- Разработка КД (даты план/факт): из проекта, на который ссылается заказ
            insert into mfr_docs_infos_states(info_id, mfr_doc_id, state_id, name, d_plan, d_fact)
            select inf.info_id, inf.mfr_doc_id, st.state_id, st.name, pt.d_to, 
                isnull(pt.d_to_fact, case when pt.progress = 1 then pt.d_to end)
            from sdocs mfr
                join mfr_docs_infos inf on inf.mfr_doc_id = mfr.doc_id
                    join @infos i on i.id = inf.info_id
                join mfr_docs_infos_states_refs st on st.state_id = 2
                join projects_tasks pt on pt.task_id = mfr.project_task_id

        -- Обеспечение материалами (план/факт): факт - max(дата прихода) для 100% обеспечения
            insert into mfr_docs_infos_states(info_id, mfr_doc_id, state_id, name, d_plan, d_fact)
            select inf.info_id, inf.mfr_doc_id, st.state_id, st.name, pl.d_plan, 
                case
                    when inf.mat_k_provided >= 0.999 then f.d_fact
                end
            from sdocs mfr
                join mfr_docs_infos inf on inf.mfr_doc_id = mfr.doc_id
                    join @infos i on i.id = inf.info_id
                join mfr_docs_infos_states_refs st on st.state_id = 3
                -- plan
                left join (
                    select mfr_doc_id, d_plan = max(opers_to_plan)
                    from sdocs_mfr_contents
                    where is_buy = 1
                    group by mfr_doc_id
                ) pl on pl.mfr_doc_id = mfr.doc_id
                -- fact
                left join (
                    select mfr_doc_id, d_fact = max(d_ship)
                    from mfr_r_provides
                    group by mfr_doc_id
                ) f on f.mfr_doc_id = mfr.doc_id

        -- Начало производства (план/факт): план - min(“Дата от (ПДО)” по деталям), факт - минимальная дата сменного задания
            insert into mfr_docs_infos_states(info_id, mfr_doc_id, state_id, name, d_plan, d_fact)
            select inf.info_id, inf.mfr_doc_id, st.state_id, st.name, pl.d_from_plan, f.d_from_fact
            from sdocs mfr
                join mfr_docs_infos inf on inf.mfr_doc_id = mfr.doc_id
                    join @infos i on i.id = inf.info_id
                join mfr_docs_infos_states_refs st on st.state_id = 4
                -- plan
                left join (
                    select mfr_doc_id, d_from_plan = min(opers_from_plan)
                    from sdocs_mfr_contents
                    where is_buy = 0
                    group by mfr_doc_id
                ) pl on pl.mfr_doc_id = mfr.doc_id
                -- fact
                left join (
                    select jd.mfr_doc_id, d_from_fact = min(e.d_doc)
                    from mfr_plans_jobs_details jd
                        join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
                        join mfr_plans_jobs_executors e on e.detail_id = jd.id
                    where j.status_id >= 0
                    group by jd.mfr_doc_id
                ) f on f.mfr_doc_id = mfr.doc_id

        -- Завершение производства (план/факт)
            insert into mfr_docs_infos_states(info_id, mfr_doc_id, state_id, name, d_plan, d_fact)
            select inf.info_id, inf.mfr_doc_id, st.state_id, st.name, mfr.d_issue_plan, mfr.d_issue
            from sdocs mfr
                join mfr_docs_infos inf on inf.mfr_doc_id = mfr.doc_id
                    join @infos i on i.id = inf.info_id
                join mfr_docs_infos_states_refs st on st.state_id = 5

    -- Непрерывность исполнения заказа:
        -- Максимальный простой, дн: по сделанным операциям
            update x set 
                cont_downtime = o.d_diff
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select lk.mfr_doc_id, d_diff = max(datediff(d, o1.d_to_fact, e.d_doc))
                    from sdocs_mfr_opers_links lk
                        join sdocs_mfr_opers o1 on o1.oper_id = lk.source_id
                            join sdocs_mfr_contents c1 on c1.content_id = o1.content_id and c1.is_buy = 0
                        join sdocs_mfr_opers o2 on o2.oper_id = lk.target_id
                            join mfr_plans_jobs_details jd on jd.oper_id = o2.oper_id
                                join mfr_plans_jobs_executors e on e.detail_id = jd.id
                        join sdocs_mfr_contents c on c.content_id = lk.content_id and c.is_buy = 0
                    where o1.d_to_fact is not null
                    group by lk.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id        

        -- Максимальный текущий простой, дн: по текущим операциям (статусы: Готов к выдаче, В работе) и = max(Текущая дата - Дата завершения предыдущей операции)
            update x set 
                cont_downtime_current = o.d_diff
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select o.mfr_doc_id, d_diff = max(datediff(d, o.d_from_plan, @today))
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 0
                    where o.status_id in (1,2)
                    group by o.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id

        -- Затягивание исполнения, дн: по операциям “Есть назначения” и = Текущая дата - Дата назначения
            update x set 
                cont_exec_delay = o.d_diff
            from mfr_docs_infos x
                join @infos i on i.id = x.info_id
                join (
                    select o.mfr_doc_id, d_diff = max(datediff(d, e.d_doc, @today))
                    from sdocs_mfr_opers o
                        join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 0
                        join mfr_plans_jobs_details jd on jd.oper_id = o.oper_id
                            join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id and j.status_id >= 0
                            join mfr_plans_jobs_executors e on e.detail_id = jd.id
                    where o.status_id = -2
                    group by o.mfr_doc_id
                ) o on o.mfr_doc_id = x.mfr_doc_id
    
    -- Синхронность исполнения:
        delete x from mfr_docs_infos_syncs x
            join @infos i on i.id = x.info_id
        
        create table #sync(
            id int identity primary key,
            info_id int,
            mfr_doc_id int,
            -- 
            content_id int index ix_content,
            delay int
            )
        
        insert into #sync(info_id, mfr_doc_id, content_id, delay)
        select x.info_id, x.mfr_doc_id, c.content_id, 
            max(datediff(d, d_to_plan, @today))
        from mfr_docs_infos x
            join @infos i on i.id = x.info_id
            join sdocs_mfr_opers o on o.mfr_doc_id = x.mfr_doc_id
                join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_buy = 0
        where c.status_id != 100
            and o.d_to_plan < @today
        group by x.info_id, x.mfr_doc_id, c.content_id

        declare @top int = 0.2 * (select count(*) from #sync)
        if @top < 20 set @top = 20

        insert into mfr_docs_infos_syncs(info_id, mfr_doc_id, content_id, name, delay)
        select top(@top) x.info_id, x.mfr_doc_id, x.content_id, c.name, x.delay from #sync x
            join sdocs_mfr_contents c on c.content_id = x.content_id
        order by x.mfr_doc_id, delay desc

        exec drop_temp_table '#sync'
end
go

-- exec mfr_docs_infos_calc 1000, @doc_id = 608172, @trace = 1
-- exec mfr_docs_infos_calc 1000, @info_id = 1
