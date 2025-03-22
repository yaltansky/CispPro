if object_id('projects_calc_resources') is not null drop procedure projects_calc_resources
go
create proc projects_calc_resources
as
begin

    -- exec project_tasks_calc_resources

    declare @d_doc date = dbo.today()

    -- #resources
        create table #resources(
            project_id int,
            task_id int,
            resource_id int,
            completed bit,
            d_doc date,
            rs_quantity float,
            rs_value float,
            index ix_group(project_id, resource_id, d_doc)
            )

        insert into #resources(
            project_id, task_id, completed, resource_id, d_doc, rs_quantity, rs_value
            )
        select t.project_id, t.task_id, 
            completed = case
                when isnull(t.progress, 0) = 1 then 1
                else 0
            end,
            c.resource_id, c.d_doc,
            c.quantity,
            c.quantity * rs.price
        from projects_resources_charts c
            join projects_tasks t on t.task_id = c.task_id
            join projects_resources rs on rs.resource_id = c.resource_id
        where c.quantity > 0
AND T.PROJECT_ID = 23846

    create table #projects(project_id int primary key)
        insert into #projects
        select distinct project_id
        from #resources

    -- #resources_fact
        create table #resources_fact(
            project_id int,
            mol_id int,
            d_doc date,
            resource_id int,
            fact_q float,
            fact_v float
            )
        insert into #resources_fact(
            project_id, mol_id, d_doc, resource_id, fact_q
            )
        select ts.project_id, ts.mol_id, td.d_doc, resource_id = isnull(mols.resource_id, depts.resource_id), td.fact_h
        from projects_timesheets_days td
            join projects_timesheets ts on ts.timesheet_id = td.timesheet_id
                join #projects p on p.project_id = ts.project_id
                join mols on mols.mol_id = ts.mol_id
                    left join depts on depts.dept_id = mols.dept_id
        where td.fact_h > 0

        update x set fact_v = fact_q * rs.price
        from #resources_fact x
            join projects_resources rs on rs.resource_id = x.resource_id

    ;with 
        pv as (
            select project_id, rs_quantity = sum(rs_quantity), rs_value = sum(rs_value)
            from #resources
            where d_doc <= @d_doc
            group by project_id
        ),
        ev as (
            select project_id, rs_quantity = sum(rs_quantity), rs_value = sum(rs_value)
            from #resources
            where completed = 1
                and d_doc <= @d_doc
            group by project_id
            ),
        ac as (
            select x.project_id, rs_value = sum(x.fact_v)
            from #resources_fact x
            where x.d_doc <= @d_doc
            group by x.project_id
            )
        update p set
            mx_ev = x.ev,
            mx_pv = x.pv,
            mx_ac = x.ac,
            mx_cv = x.cv,
            mx_sv = x.sv,
            mx_cpi = x.cpi,
            mx_spi = x.spi
        from projects p
            join (
                select x.*,
                    cv = ev - ac,
                    sv = ev - pv,
                    cpi = round(ev / nullif(ac, 0), 4),
                    spi = round(ev / nullif(pv, 0), 4)
                from (
                    select p.project_id,
                        pv = isnull(pv.rs_value, 0),
                        ev = isnull(ev.rs_value, 0),
                        ac = isnull(ac.rs_value, 0)
                    from #projects p
                        left join pv on pv.project_id = p.project_id
                        left join ev on ev.project_id = p.project_id
                        left join ac on ac.project_id = p.project_id
                    ) x                
            ) x on x.project_id = p.project_id


        create table #resources_az(
            project_id int,
            resource_id int,
            d_doc date,
            limit_q float,
            limit_v float,
            price float,
            -- 
            task_id int,
            plan_q float,
            plan_v float,
            -- 
            mol_id int,
            fact_q float,
            fact_v float,
            index ix_group(project_id, resource_id, d_doc, task_id, mol_id)
        )

    -- plan_q/v
        insert into #resources_az(
            project_id, resource_id, d_doc, task_id, plan_q, plan_v
            )
        select
            x.project_id, x.resource_id, x.d_doc, x.task_id, x.quantity, x.quantity * rs.price
        from projects_resources_charts x
            join projects_resources rs on rs.resource_id = x.resource_id
            join #projects i on i.project_id = x.project_id

    -- fact_q/v
        insert into #resources_az(
            project_id, resource_id, d_doc, mol_id, fact_q, fact_v
            )
        select
            x.project_id, x.resource_id, x.d_doc, x.mol_id, x.fact_q, x.fact_v
        from #resources_fact x

    delete x from projects_resources_az x
        join #projects p on p.project_id = x.project_id

    insert into projects_resources_az(
        project_id, resource_id, d_doc, limit_q, limit_v, price, task_id, plan_q, plan_v, mol_id, fact_q, fact_v
        )
    select 
        x.project_id,
        x.resource_id, x.d_doc, rs.limit_q, rs.limit_q * rs.price, price, 
        x.task_id, plan_q, plan_v,
        x.mol_id, fact_q, fact_v
    from (
        select project_id, resource_id, d_doc, task_id, mol_id,
            plan_q = sum(plan_q), 
            plan_v = sum(plan_v), 
            fact_q = sum(fact_q), 
            fact_v = sum(fact_v)
        from #resources_az
        group by project_id, resource_id, d_doc, task_id, mol_id
        ) x
        join projects_resources rs on rs.resource_id = x.resource_id

    exec drop_temp_table '#resources,#projects,#resources_fact,#resources_az'
end
GO
