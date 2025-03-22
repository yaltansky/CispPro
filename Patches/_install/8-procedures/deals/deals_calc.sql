if object_id('deals_calc') is not null drop procedure deals_calc
go
create proc deals_calc
	@all bit = 0,
    @manager_id int = null,
    @deals app_pkids readonly
as
begin
	set nocount on;

	create table #deals(id int primary key)

    declare @filter_deals bit = case when exists(select 1 from @deals) then 1 else 0 end

    -- left_ccy
        declare @deals_left_ccy app_pkids

        update x
        set left_ccy = x.value_ccy - fd.value_rur
        output inserted.deal_id into @deals_left_ccy
        from deals x
            join deals_statuses s on s.status_id = x.status_id
            join (
                select d.deal_id, sum(f.value_rur) as value_rur
                from findocs# f
                    join deals d on d.budget_id = f.budget_id
                where f.article_id = 24
                group by d.deal_id
            ) fd on fd.deal_id = x.deal_id
        where (@all = 1 or s.is_current = 1)
            and (@manager_id is null or x.manager_id = @manager_id)
            and (@filter_deals = 0 or x.deal_id in (select id from @deals))

        if exists(select 1 from @deals) insert into #deals select id from @deals
        else insert into #deals select id from @deals_left_ccy
        
        if not exists(select 1 from #deals)
            return -- nothing todo

    -- auto-status
        update x
        set status_id = 35 -- Исполнен
        from deals x
            join #deals i on i.id = x.deal_id
        where left_ccy = 0
            and status_id = 32 -- В работе

    -- auto-name
        update x
        set name = xx.name
        from budgets x
            join (
                select
                    budget_id,
                    concat(number,
                        ': ',
                            a.name, ', ',
                            deals.spec_number, case when deals.spec_number is not null then ', ' end,
                            deals.value_ccy, ' RUR',
                            case
                                when deals.left_ccy is not null then concat(' (ост. ', deals.left_ccy, ')')
                            end
                        ) as name
                from deals
                    join #deals xd on xd.id = deals.deal_id
                    join agents a on a.agent_id = deals.customer_id
            ) xx on xx.budget_id = x.budget_id
        where x.name != xx.name

    -- access
        if @all = 0
        begin
            delete x from projects_mols x
                join #deals i on i.id = x.project_id
            where response in ('deals.reader', '#auto')
                
            -- deals.reader
            insert into projects_mols(project_id, mol_id, name, response)
            select d.deal_id, mm.mol_id, mm.mol_name, mm.role_name
            from deals d
                join #deals i on i.id = d.deal_id
                join (
                    select ro.objectid as vendor_id, m.mol_id, m.name as mol_name, r.name as role_name
                    from rolesobjects ro
                        join roles r on r.id = ro.roleid
                        join mols m on m.mol_id = ro.molid
                    where r.name = 'deals.reader'
                ) mm on mm.vendor_id = d.vendor_id

            -- #auto
            insert into projects_mols(project_id, mol_id, name, response)
            select distinct d.deal_id, mols.mol_id, mols.name, '#auto'
            from deals d
                join #deals i on i.id = d.deal_id
                join directions dd on dd.direction_id = d.direction_id
                join mols on mols.mol_id in (d.manager_id, dd.chief_id)
            where not exists(select 1 from projects_mols where project_id = d.deal_id and mol_id = mols.mol_id)    

            declare @sectionBudgets int = (select section_id from projects_sections where ikey = 'budgets')

            delete x from projects_mols_sections_meta x
                join #deals i on i.id = x.project_id
            where section_id = @sectionbudgets

            insert into projects_mols_sections_meta(project_id, tree_id, section_id, a_read, a_update)
            select distinct project_id, x.id, @sectionbudgets, 1, 0
            from projects_mols x
                join #deals i on i.id = x.project_id

            declare @projects as app_pkids; insert into @projects select id from #deals
            if exists(select 1 from @projects)
                exec project_mols_calc @projects = @projects
        end

    -- patch on BAD projects
        if db_name() = 'CISP'
        begin
            SET IDENTITY_INSERT CISP_SHARED..PROJECTS ON
            EXEC SYS_SET_TRIGGERS 0

                -- append projects
                insert into projects(
                    project_id, template_id, type_id, budget_type_id, subject_id, status_id,
                    name, d_from, number, agent_id, curator_id, chief_id, admin_id, note,
                    add_date
                    )
                select
                    x.deal_id, 101,
                    3, -- type_id
                    2, -- budget_type_id
                    x.subject_id,
                    isnull(x.status_id, 20),
                    number + ' ' + a.name,
                    isnull(x.spec_date, dbo.today()),
                    number, customer_id,
                    -25,
                    x.manager_id,
                    -25,
                    '#normalized by deals_calc',
                    getdate()
                from deals x
                    join budgets b on b.budget_id = x.budget_id
                    join agents a on a.agent_id = x.customer_id
                where x.deal_id in (
                    select deal_id
                    from deals d
                        join budgets b on b.budget_id = d.budget_id
                    where project_id is not null
                        and not exists(select 1 from projects where project_id = b.project_id)
                    )

            SET IDENTITY_INSERT CISP_SHARED..PROJECTS OFF
            EXEC SYS_SET_TRIGGERS 1
        end
end
go
