if object_id('deals_upload') is not null drop procedure deals_upload
go
create proc deals_upload
	@mol_id int,
	@group_id uniqueidentifier,
	@trace bit = 0
as begin
	set nocount on;

    -- tracer
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

        declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
            ' @mol_id=', @mol_id,
            ' @group_id=', @group_id
            )
        exec tracer_log @tid, @tid_msg

    -- tables
        -- #deals
            create table #deals(
                id int identity,
                upload_id int,
                    subject_id int,
                    subject_pred_name varchar(100),
                    project_id int,
                    deal_id int,
                    DocID int not null default(0) index ix_doc_id,
                    external_id int,	
                d_doc datetime,
                    number varchar(50),		
                status_id int,
                place_name varchar(50),
                    vendor_id int,
                dogovor_id int,
                    dogovor_number varchar(50),
                    dogovor_date datetime,
                    dogovor_ccy_id char(3),
                appoval_sheet_number varchar(50),
                    appoval_sheet_date datetime,
                spec_id int,
                    spec_number varchar(100),
                    spec_date datetime,
                crm_number varchar(250),
                    crm_date datetime,
                customer_id int,
                    customer_name varchar(250),
                    customer_city varchar(500),
                    customer_country varchar(50),
                    customer_type_id varchar(32),
                    customer_type_name varchar(50),
                consumer_id int,
                    consumer_name varchar(250),
                ccy_id varchar(3),
                value_ccy decimal(18,2),
                rate_fin float,
                delivery_basis_id varchar(50),
                    delivery_basis_note varchar(50),
                    duration_delivery int,
                    duration_delivery_from_id varchar(32),
                    duration_delivery_from varchar(50),
                    delivery_days_shipping int,
                    duration_manufacture int,
                    duration_reserveshipping int,
                    delivery_days_mounting int,
                    delivery_misc_term varchar(255),
                direction_id varchar(32),
                    direction_name varchar(100),
                    direction_boss_id int,
                manager_id int,
                    manager_name varchar(100),
                admin_id int,
                    ver_date datetime,
                    ver_number varchar(20),
                note varchar(max),
                eProjectID int,
                eProjectName varchar(255),
                errors varchar(max)
            )
        -- #mols
            create table #mols(
                DocID int index ix_doc_id,
                manager_id int,
                manager_name varchar(50),
                Kv float,
                Kc float,
                note varchar(50)
            )
        -- #products
            create table #products(
                DocID int index ix_doc_id,
                ExtID int,
                name varchar(250),
                ProductID int,
                UnitName varchar(20),
                MfrDocList varchar(max),
                quantity float,
                price_pure float,
                price_transfer_pure float,
                value_bdr float,
                value_transfer_pure float,
                value_bds float,
                value_transfer float,
                --
                nds_ratio decimal(2,2),
                value_nds decimal(18,2)
            )
        -- #pays
            create table #pays(
                DocID int index ix_doc_id,
                PayNo int,
                instant_id int,
                instant_name varchar(50),
                task_id int,
                article_id int default 24,
                date_lag int,
                ratio float,
                value_bdr decimal(18,2),
                value_nds decimal(18,2),
                value_bds decimal(18,2)
            )
        -- #expenses
            create table #expenses(
                DocID int index ix_doc_id,
                alias_id int,
                alias_name varchar(250),
                task_id int,
                article_id int,
                value_bdr decimal(18,2),
                nds_ratio decimal(18,2),
                value_nds decimal(18,2),
                value_bds decimal(18,2)
            )

    begin try
        declare c_deals cursor local read_only for 
            select upload_id from deals_uploads where group_id = @group_id
        
        declare @upload_id int
        
        open c_deals; fetch next from c_deals into @upload_id
            while (@@fetch_status <> -1)
            begin
                -- print concat('parse ', @upload_id)
                if (@@fetch_status <> -2) exec deals_upload;2 @upload_id
                fetch next from c_deals into @upload_id
            end
        close c_deals; deallocate c_deals

        exec deals_upload;3 -- prepare columns
    end try
    begin catch
        declare @err varchar(max) set @err = error_message()
        raiserror (@err, 16, 1)
        close c_deals; deallocate c_deals
        goto finish
    end catch -- parse

    -- check
        -- check on single subject
        if (select count(distinct subject_id) from #deals) > 1
        begin
            raiserror('Набор сделок должен относиться к одному субъекту учёта.', 16, 1)
            return
        end

        -- check uniqness of number
        if exists(select 1 from #deals group by number having count(*) > 1)
        begin
            declare @numbers varchar(max) = (
                select number + ','  [text()] from 
                    #deals group by number having count(*) > 1
                    for xml path('')
                )
            set @numbers = substring(@numbers, 1, len(@numbers) - 1)
            raiserror('В наборе сделок должен быть уникальный номер сделки. Проверьте входящие документы: %s.', 16, 1, @numbers)

            select * from #deals order by number
            return
        end

	exec deals_upload;10 @tid

    -- post process
        update x
        set external_id = -x.deal_id
        from deals x
            join #deals xx on xx.deal_id = x.deal_id
        where x.deal_id < 0 -- обратная совместимость с deals_replicate (для старых сделок)

        -- deal_id
        update x set deal_id = xx.deal_id
        from deals_uploads x
            join #deals xx on xx.upload_id = x.upload_id

        -- buffer
        declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
        
        delete from objs_folders_details where folder_id = @buffer_id
        
        insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
        select @buffer_id, 'DL', deal_id, @mol_id
        from #deals
        where deal_id is not null

    finish:
        exec tracer_close @tid
        if @trace = 1 exec tracer_view @tid

    -- drop #tables
        drop table #deals, #mols, #pays, #products, #expenses
end
go
-- helper: parse xml
create proc deals_upload;2
	@upload_id int
as begin
    -- @xml
        declare @xml xml = (select data from deals_uploads where upload_id = @upload_id)

    -- @handle_xml prepare
        declare @handle_xml int; exec sp_xml_preparedocument @handle_xml output, @xml

    -- @errors
        declare @errors table(error varchar(8000))
        insert into @errors(error) select error
        from openxml (@handle_xml, '/Deal/Errors/*', 2) with (error varchar(500) 'text()')

        declare @error varchar(max)
        if exists(select 1 from @errors)
        begin
            set @error = (select error + ' '  [text()] from @errors for xml path(''))
            update deals_uploads 	set errors = @error 	where upload_id = @upload_id
            goto finish		
        end

    -- #deals
        insert into #deals (
            upload_id,
            subject_pred_name,
            d_doc,
            number,
            place_name,
            dogovor_number,
            dogovor_date,
            appoval_sheet_number,
            appoval_sheet_date,
            spec_number,
            spec_date,
            crm_number,
            crm_date,
            customer_name,
            customer_country,
            customer_type_name,
            consumer_name,
            ccy_id,
            rate_fin,
            delivery_basis_id,
            delivery_basis_note,
            duration_delivery,
            duration_delivery_from,
            delivery_days_shipping,
            duration_manufacture,
            duration_reserveshipping,
            delivery_days_mounting,
            direction_name,
            manager_name,
            ver_date,
            ver_number,
            note
        )
        select @upload_id, * from openxml (@handle_xml, '/Deal', 2) with (
            SubjectName varchar(100),
            DocDate datetime,
            DocNo varchar(50),
            MfrName varchar(50),
            AgreeNo varchar(50),
            AgreeDate datetime,
            ApprovalSheetNo varchar(50),
            ApprovalSheetDate datetime,
            SpecNo varchar(50),
            SpecDate datetime,
            CrmNo varchar(50),
            CrmDate datetime,
            AgentName varchar(250),
            AgentCountry varchar(100),
            AgentTypeName varchar(50),			
            AgentDstName varchar(250),
            CcyID varchar(3),
            RateFin float,
            DeliveryBase varchar(50),				
            DeliveryBaseNote varchar(100),
            DeliveryPeriod int,
            DeliveryPeriodFrom varchar(50),
            DeliveryDay int,
            MfrDay int,
            ReserveDay int,
            MountDay int,
            DepName varchar(100),
            ManagerName varchar(100),
            VerDate datetime,
            VerNo varchar(20),
            Memo varchar(max)
            )

    -- DocId, deal_id	
        declare @seed_id int = isnull((select max(project_id) from projects), 0)
        declare @id int = @@identity
        declare @doc_id int = @seed_id + @id

    /** DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG **/
    --	UPDATE #DEALS SET NUMBER = 'T:' + NUMBER WHERE ID = @ID
    /** DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG **/

        update #deals 
        set DocId = @doc_id,
            project_id = @doc_id		
        where id = @id
        
        update x
        set @doc_id = d.deal_id,
            DocId = @doc_id,		
            deal_id = d.deal_id,
            project_id = d.deal_id
        from #deals x
            join deals d on d.number = x.number
        where x.id = @id

    -- subject_id	
        update x
        set subject_id = s.subject_id
        from #deals x
            join agents a on a.name = x.subject_pred_name
                join subjects s on s.pred_id = isnull(a.main_id, a.agent_id)
        where x.id = @id

        if exists(select 1 from #deals where id = @id and subject_id is null)
            set @error = concat(@error, case when @error is not null then '. ' end,
                'Не удалось идентифицировать субъект учёта по названию контрагента ', 
                (select subject_pred_name from #deals where id = @id)
                )

    -- #mols
        insert into #mols(DocId, manager_name, Kv, Kc)
        select @doc_id, * from openxml (@handle_xml, '/Deal/Mols/DealMol', 2) with (
            ManagerName varchar(50),
            Kv float,
            Kc float
            )
        
    -- #products
        insert into #products(
            DocId, 
            ExtID,
            name,
            quantity,
            price_pure,
            price_transfer_pure,
            value_bdr,
            value_transfer_pure,
            value_bds,
            value_transfer	
            )
        select @doc_id, * from openxml (@handle_xml, '/Deal/Products/DealProduct', 2) with (
            ExtID int,
            ProductName varchar(250),
            Q float,
            Pc float,
            PcTrf float,
            SumPc float,
            SumTrf float,
            SumTotal float,
            SumTrfTotal float
            )

    -- #pays
        insert into #pays(
            DocID,
            instant_name,
            date_lag,
            ratio,
            value_bds
            )
        select @doc_id, * from openxml (@handle_xml, '/Deal/Pays/DealPay', 2) with (
            InstantName varchar(50),
            PeriodDay int,
            PortionPercent float,
            PaySum float
            )
        update #pays set instant_name = ltrim(rtrim(instant_name))

    -- #expenses
        insert into #expenses(
            DocID, alias_name, value_bdr, nds_ratio, value_bds)
        select 
            @doc_id, Analyt, SumPc, 0.2, SumTotal
        from openxml (@handle_xml, '/Deal/Expenses/DealExpense', 2) with (
            Analyt varchar(250),
            SumPc float,
            SumTotal float
            )

        update deals_uploads set errors = @error where upload_id = @upload_id
        update #deals set errors = @error where id = @id

    -- @handle_xml remove
    finish:
        exec sp_xml_removedocument @handle_xml
end
go
-- helper: prepare columns
create proc  deals_upload;3
as begin

	declare @admin_id int = -25
	
    -- #deals
        update #deals set admin_id = @admin_id

        -- map existed deals
        update x
        set project_id = xx.deal_id,
            deal_id = xx.deal_id,
            status_id = isnull(x.status_id, p.status_id)
        from #deals x
            join deals xx on xx.number = x.number
                left join projects p on p.project_id = xx.deal_id

        -- vendor_id
        update x
        set vendor_id = isnull(xx.subject_id, -12),
            note = concat(x.note,
                case 
                    when xx.subject_id is null then concat(case when x.note is null then '' else ' ,' end, 'площадка=', x.place_name) 
                    else '' end
                )
        from #deals x
            left join subjects xx on xx.name = x.place_name or isnull(xx.short_name, '') = isnull(x.place_name, '')

        -- #agents
        insert into agents(name, name_print)
        select distinct name, name
        from (
            select customer_name as name from #deals
            union select consumer_name from #deals
            ) u
        where name is not null
            and not exists(select 1 from agents where name = u.name)

        -- customer_id
        update x
        set customer_id = a.agent_id
        from #deals x
            join agents a on a.name = x.customer_name

        -- consumer_id
        update x
        set consumer_id = a.agent_id
        from #deals x
            join agents a on a.name = x.consumer_name

        -- customer_type_id
        insert into options_lists(l_group, id, name)
        select distinct 'DealMarketing', 'DealMark' + customer_type_id, customer_type_name from #deals
        where customer_type_id is not null
            and customer_type_name not in (select name from options_lists where l_group = 'DealMarketing')

        update x
        set customer_type_id = xx.id,
            note = isnull(x.note,'') + case when xx.id is null then ', тип покупателя=' + x.customer_type_name else '' end
        from #deals x
            left join options_lists xx on xx.l_group = 'DealMarketing' and xx.name = x.customer_type_name
        
        -- duration_delivery_from_id
        update x
        set duration_delivery_from_id = xx.id
        from #deals x
            left join options_lists xx on xx.l_group = 'DeliveryFrom' and xx.name = x.duration_delivery_from

        -- direction_id
        update x
        set direction_id = xx.dept_id
        from #deals x
            join deals_map_directions xx on xx.name = x.direction_name
                join depts on depts.dept_id = xx.dept_id and depts.subject_id = x.subject_id

        -- manager_id
        update x
        set direction_id = isnull(x.direction_id, xx.dept_id),
            direction_boss_id = isnull(xx.chief_id, -@admin_id),
            manager_id = isnull(xx.mol_id, @admin_id),
            note = concat(
                x.note, 
                case when isnull(x.note,0) = '' then '' else ', ' end,
                case when xx.mol_id is null then 'менеджер=' + x.manager_name + ', ' else '' end
                )
        from #deals x
            left join mols xx on xx.name = replace(x.manager_name, '. ', '.')

    -- #mols
        if object_id('tempdb.dbo.#mols') is not null
        begin
            -- defaults
            insert into #mols(DocID, manager_id, manager_name, Kv, Kc)
            select x.DocID, x.manager_id, x.manager_name, 1, 1
            from #deals x
            where not exists(select 1 from #mols where DocId = x.DocID)

            -- manager_id
            update x
            set manager_id = xx.mol_id,
                note = case when xx.mol_id is null then x.manager_name end
            from #mols x
                left join mols xx on xx.name = x.manager_name
        end

        declare @value_nds decimal(18,2)

    -- #products
        if object_id('tempdb.dbo.#products') is not null
        begin	
            update #products
            set @value_nds = value_bds - value_bdr,
                nds_ratio = @value_nds / nullif(value_bdr,0),
                value_nds = @value_nds
            
            -- value_ccy
            update x
            set value_ccy = (select sum(value_bds) from #products where DocID = x.DocID)
            from #deals x
        end

    -- #pays
        if object_id('tempdb.dbo.#pays') is not null
        begin
            update x
            set instant_id = m.instant_id
            from #pays x
                join deals_map_instants m on m.instant_name = x.instant_name

            -- value_bdr, value_nds, value_bds
            declare @nds_ratio decimal(18,2), @value_bdr decimal(18,2), @value_bds decimal(18,2)

            update x
            set @nds_ratio = (select max(nds_ratio) from #products where DocID = x.DocID),		
                @value_bds = x.ratio * xx.value_ccy,
                @value_bdr = @value_bds / ( 1 + @nds_ratio),
                value_bdr = @value_bdr,
                value_nds = @value_bds - @value_bdr,
                value_bds = @value_bds
            from #pays x
                join #deals xx on xx.DocID = x.DocID
        end

    -- #expenses
	update #expenses
	set @value_nds = value_bds - value_bdr,
		nds_ratio = isnull(@value_nds / nullif(value_bdr,0), 0),
		value_nds = @value_nds
	
	update x
	set alias_id = m.alias_id,
		article_id = isnull(m.article_id, 18) -- прочие расходы
	from #expenses x
		left join deals_map_aliases m on m.alias_name = x.alias_name
end
go
-- creating deals
create proc deals_upload;10
	@tid int
as
begin
	declare @today datetime = dbo.today()	
	declare @tid_msg varchar(max)
	declare @template_id int = 101

    BEGIN TRY
    BEGIN TRANSACTION

    exec tracer_log @tid, 'auto creating docs'
    begin
        -- договора покупателей
        insert into deals_docs(type_id, d_doc, number)
        select 1, d_doc, number
        from (
            select d_doc = isnull(dogovor_date,0), number = dogovor_number
            from #deals
            group by dogovor_date, dogovor_number
        ) x
        where isnull(number, '') <> ''
            and not exists(select 1 from deals_docs where type_id = 1 and d_doc = x.d_doc and number = x.number)

        -- спецификации договоров покупателей
        insert into deals_docs(type_id, d_doc, number)
        select 2, d_doc, number
        from (
            select d_doc = isnull(spec_date,0), number = spec_number
            from #deals
            group by spec_date, spec_number
        ) x
        where isnull(number, '') <> ''
            and not exists(select 1 from deals_docs where type_id = 2 and d_doc = x.d_doc and number = x.number)

        -- map dogovor_id
        update x set dogovor_id = xx.doc_id
        from #deals x
            left join deals_docs_dogovors xx on xx.d_doc = isnull(x.dogovor_date,0) and xx.number = x.dogovor_number

        -- map spec_id
        update x set spec_id = xx.doc_id
        from #deals x
            left join deals_docs_specs xx on xx.d_doc = isnull(x.spec_date,0) and xx.number = x.spec_number

    end -- auto creating docs

    exec tracer_log @tid, 'creating projects'
    begin
        create table #map_projects (DocId int primary key, project_id int, is_new bit)
        create unique index ix_map_projects on #map_projects(project_id)

        SET IDENTITY_INSERT CISP_SHARED..PROJECTS ON
        EXEC SYS_SET_TRIGGERS 0

            -- append
            insert into projects(
                project_id, template_id, type_id, budget_type_id, subject_id, status_id, name, d_from, add_date, number, agent_id, curator_id, chief_id, admin_id, note
                )
                output inserted.template_id, inserted.project_id, 1 into #map_projects
            select 
                project_id, DocID, 
                3, -- type_id
                2, -- budget_type_id
                x.subject_id,
                isnull(x.status_id, 20),
                number + ' ' + x.customer_name,
                isnull(x.spec_date, @today),
                isnull(x.spec_date, @today),
                number, customer_id,
                x.direction_boss_id,
                x.manager_id,
                x.admin_id,
                note
            from #deals x
            where x.deal_id is null
                and not exists(select 1 from projects where project_id = x.project_id)

        SET IDENTITY_INSERT CISP_SHARED..PROJECTS OFF
        EXEC SYS_SET_TRIGGERS 1

            set @tid_msg = concat(@@rowcount, ' projects inserted')
            exec tracer_log @tid, @tid_msg

            -- update
            update x set number = xx.number
                output inserted.project_id, inserted.project_id, 0 into #map_projects
            from projects x
                join #deals xx on xx.project_id = x.project_id		
            where not exists(select 1 from #map_projects where DocId = xx.DocID)

            -- mapping
            update x
            set template_id = @template_id
            from projects x
                join #map_projects m on m.project_id = x.project_id

            update x
            set deal_id = m.project_id
            from #deals x
                join #map_projects m on m.DocId = x.DocID

            -- projects_mols
            insert into projects_mols(project_id, name, mol_id, response)
            select distinct u.project_id, mols.name, mols.mol_id, response
            from (
                select project_id, direction_boss_id as mol_id, 'Куратор сделки' as response from #deals
                ) u
                join mols on mols.mol_id = u.mol_id
            where not exists(select 1 from projects_mols where project_id = u.project_id and mol_id = u.mol_id)

        if exists(select 1 from #map_projects where is_new = 1)
        begin
        exec tracer_log @tid, 'creating projects_tasks'
            create table #map (
                project_id int, source_id int, target_id int,
                constraint pk_map primary key (project_id, source_id)
                )
                
            exec sys_set_triggers 0
                insert into projects_tasks(project_id, template_task_id, parent_id, task_number, name, duration, duration_input, duration_id, predecessors, node, has_childs, outline_level, sort_id)
                    output inserted.project_id, inserted.template_task_id, inserted.task_id into #map
                select m.project_id, task_id, parent_id, task_number, name, duration, duration_input, duration_id, predecessors, node, has_childs, outline_level, sort_id
                from projects_tasks as tpl
                    join #map_projects m on m.is_new = 1
                where tpl.project_id = @template_id
                order by m.project_id, tpl.node
            exec sys_set_triggers 1

            set @tid_msg = concat(@@rowcount, ' projects tasks inserted')
            exec tracer_log @tid, @tid_msg
        
                -- mapping
                update x
                set parent_id = m.target_id
                from projects_tasks x
                    join #map m on m.project_id = x.project_id and m.source_id = x.parent_id
        
                -- links
                insert into projects_tasks_links(project_id, source_id, target_id, type_id)
                select m1.project_id, m1.target_id, m2.target_id, l.type_id
                from projects_tasks_links l			
                    join #map m1 on m1.source_id = l.source_id
                    join #map m2 on m2.project_id = m1.project_id and m2.source_id = l.target_id
                where l.project_id = @template_id			

            drop table #map

            set @tid_msg = concat(@@rowcount, ' projects tasks links inserted')
            exec tracer_log @tid, @tid_msg
        end

    exec tracer_log @tid, 'mapping projects_tasks'
        exec tracer_log @tid, '    #pays.task_id'

        update x
        set task_id = t.task_id
        from #pays x
            join deals_map_instants xx on xx.instant_id = x.instant_id
                join #map_projects p on p.DocId = x.DocID
                    join projects_tasks t on t.project_id = p.project_id and t.name = xx.task_name

    -- SELECT * FROM #PAYS

        if exists(select 1 from #pays where task_id is null)
        begin
            select * from #pays x where task_id is null
            raiserror('Не удалось идентифицировать Ганта с графиком платежей (#pays).<end>', 16, 1)
        end

        exec tracer_log @tid, '    #expenses.task_id'	
        update x set task_id = t.task_id		
        from #expenses x
            join deals_map_aliases xx on xx.alias_id = x.alias_id
                join #map_projects p on p.DocId = x.DocID
                    join projects_tasks t on t.project_id = p.project_id and t.name = xx.task_name

        drop table #map_projects
    end -- creating projects

    exec tracer_log @tid, 'creating deals'
    begin

        select * into #deleted from deals where deal_id in (select deal_id from #deals)
        select * into #deals_products from deals_products where deal_id in (select deal_id from #deals) -- ... then restore
        select * into #deals_costs from deals_costs where deal_id in (select deal_id from #deals) -- ... then restore

        delete from deals where deal_id in (select deal_id from #deals)

        if exists(
            select 1 from deals where number in (select number from #deals)
            )
        begin
            declare @numbers varchar(max) = (
                select number + ','  [text()] from deals 
                where number in (select number from #deals)
                group by number
                for xml path('')
                )
            set @numbers = substring(@numbers, 1, len(@numbers) - 1)
            raiserror('Есть дублирование номеров сделок (%s). Импорт пакета приостановлен.', 16, 1, @numbers)
        end

        declare @DefBuhDogovorId int = cast(dbo.app_registry_value('DealsDefBuhDogovorId') as int);

        insert into deals(
            deal_id,
            status_id,
            subject_id,
            budget_id,
            program_id,
            --
            d_doc, number, vendor_id, mfr_name,
            --
            dogovor_id,
            dogovor_number,
            dogovor_date,
            dogovor_ccy_id,
            buh_principal_id,
            --
            spec_id, spec_number, spec_date,
            --
            appoval_sheet_number, appoval_sheet_date, crm_number, crm_date, 
            customer_id, customer_city, customer_country, customer_type_id, consumer_id, 
            direction_id, manager_id, ccy_id, value_ccy, rate_fin,
            --
            delivery_basis_id,
            delivery_basis_note,
            duration_delivery, delivery_days_shipping, duration_manufacture, duration_reserveshipping, delivery_days_mounting, duration_delivery_from_id,
            delivery_misc_term,
            --
            ver_date, ver_number,
            --
            note,
            --
            eProjectID, eProjectName
            )
        select 
            d.deal_id,
            coalesce(dd.status_id, d.status_id, 20),
            d.subject_id,
            dd.budget_id,
            dd.program_id,
            --
            d.d_doc, 
            substring(d.number, 1, 50),
            d.vendor_id,
            d.place_name,
            --
            isnull(dd.dogovor_id, d.dogovor_id),
            substring(d.dogovor_number, 1, 50),
            isnull(dd.dogovor_date, d.dogovor_date),
            isnull(dd.dogovor_ccy_id, d.dogovor_ccy_id),
            @DefBuhDogovorId,
            --
            d.spec_id,
            substring(d.spec_number, 1, 50),
            d.spec_date,
            --
            substring(d.appoval_sheet_number, 1, 50),
            d.appoval_sheet_date,
            substring(d.crm_number, 1, 50),
            d.crm_date,
            --
            d.customer_id,
            substring(d.customer_city, 1, 50),
            substring(d.customer_country, 1, 50),
            isnull(dd.customer_type_id, d.customer_type_id),
            d.consumer_id, 
            --
            isnull(dd.direction_id, d.direction_id),
            isnull(dd.manager_id, d.manager_id),
            --
            d.ccy_id, d.value_ccy, d.rate_fin,
            --
            substring(d.delivery_basis_id, 1, 16),
            substring(d.delivery_basis_note, 1, 50),
            d.duration_delivery, d.delivery_days_shipping, d.duration_manufacture, d.duration_reserveshipping, d.delivery_days_mounting, d.duration_delivery_from_id,
            d.delivery_misc_term,
            --
            d.ver_date, d.ver_number,
            --
            d.note,
            d.eProjectID, d.eProjectName
        from #deals d
            left join #deleted dd on dd.deal_id = d.deal_id

        set @tid_msg = concat(@@rowcount, ' deals inserted')
        exec tracer_log @tid, @tid_msg
        
    exec tracer_log @tid, 'deals_mols'
        insert into deals_mols(deal_id, mol_id, kv, kc, note)
        select xd.deal_id, x.manager_id, x.Kv, x.Kc, x.note
        from #mols x
            join #deals xd on xd.DocID = x.DocID

    exec tracer_log @tid, 'deals_products'
        insert into deals_products(
            deal_id, row_id, name, 
            eProductID, eUnitName, eMfrDocList,
            quantity, price_pure, price_transfer_pure, value_bdr, value_transfer_pure, nds_ratio, value_nds, value_bds, value_transfer
            )
        select 
            xx.deal_id, isnull(old.row_id, x.extid), x.name,
            x.ProductID, x.UnitName, x.MfrDocList,
            x.quantity, x.price_pure, x.price_transfer_pure, x.value_bdr, x.value_transfer_pure, x.nds_ratio, x.value_nds, x.value_bds, x.value_transfer
        from #products x
            join #deals xx on xx.DocID = x.DocID
            left join #deals_products old on old.deal_id = xx.deal_id and old.name = x.name

    exec tracer_log @tid, 'deals_costs'
        SET IDENTITY_INSERT CISP_SHARED..DEALS_COSTS ON
            insert into deals_costs(id, deal_id, deal_product_id, deal_product_name, task_id, article_id, nds_ratio, value_bdr, value_bds, value_nds, note, is_manual, is_automap)
            select id, deal_id, deal_product_id, deal_product_name, task_id, article_id, nds_ratio, value_bdr, value_bds, value_nds, note, is_manual, is_automap
            from #deals_costs x
        SET IDENTITY_INSERT CISP_SHARED..DEALS_COSTS OFF

    exec tracer_log @tid, 'deals_budgets'
        -- #pays
        insert into deals_budgets(deal_id, type_id,  task_id, date_lag, article_id, ratio, value_bdr, value_nds, value_bds)
        select xx.deal_id, 1, isnull(task_id,0), date_lag, article_id, ratio, value_bdr, value_nds, value_bds
        from #pays x
            join #deals xx on xx.DocID = x.DocID

        -- #expenses
        insert into deals_budgets(deal_id, type_id, task_id, article_id, value_bdr, nds_ratio, value_nds, value_bds)
        select xx.deal_id, 3, isnull(task_id,0), article_id, value_bdr, x.nds_ratio, value_nds, value_bds
        from #expenses x
            join #deals xx on xx.DocID = x.DocID
    end -- creating deals

    exec tracer_log @tid, 'recalc deals'
        declare @deal_ids as app_pkids;	insert into @deal_ids select deal_id from #deals
        exec deal_calc @mol_id = -25, @ids = @deal_ids, @tid = @tid

    -- map budget_id
        update x
        set budget_id = b.budget_id
        from deals x
            join #deals xx on xx.deal_id = x.deal_id
            join budgets b on b.project_id = x.deal_id
        where x.budget_id is null

    exec tracer_log @tid, 'auto-create budgets'
        declare @map_budgets table(budget_id int, deal_id int index ix_deal)
        insert into budgets(type_id, name, project_id, mol_id)
            output inserted.budget_id, inserted.project_id into @map_budgets
        select 3, x.number, x.deal_id, x.manager_id
        from deals x
            join #deals xx on xx.deal_id = x.deal_id
        where x.budget_id is null

        if exists(select 1 from @map_budgets)
        begin
            exec budgets_by_vendors_calc @news_only = 1

            update x set budget_id = m.budget_id
            from deals x
                join @map_budgets m on m.deal_id = x.deal_id
        end

        -- deals_files
        if object_id('deals_files') is not null
        begin
            delete from deals_files where deal_id in (select deal_id from #deals)

            insert into deals_files(
                deal_id, deal_doc_id, add_date, name, file_type, file_data, update_date
                )
            select 
                d.deal_id, d.deal_id, getdate(), x.file_name, 
                case
                    when len(file_name) - charindex('.', reverse(file_name)) + 2 > 0
                        then substring(file_name, len(file_name) - charindex('.', reverse(file_name)) + 2, 250)
                end,
                x.file_data,
                getdate()
            from deals_uploads x
                join #deals d on d.upload_id = x.upload_id

            update x set file_data = null -- чтобы не раздувать основную базу
            from deals_uploads x
                join #deals d on d.upload_id = x.upload_id
        end

    COMMIT TRANSACTION
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        exec sys_set_triggers 1
        declare @err varchar(max) = error_message()
        raiserror (@err, 16, 1)
    END CATCH

	if object_id('tempdb.dbo.#deleted') is not null drop table #deleted
	if object_id('tempdb.dbo.#deals_products') is not null drop table #deals_products
	if object_id('tempdb.dbo.#deals_costs') is not null drop table #deals_costs
end
go
