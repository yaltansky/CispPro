if object_id('mfr_docs_buffer_action') is not null drop proc mfr_docs_buffer_action
go
create proc mfr_docs_buffer_action
	@mol_id int,
	@action varchar(32),
	@queue_id uniqueidentifier = null,
	@priority_id int = null,
	@status_id int = null
as
begin
    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfr')
	declare @docs app_pkids

    BEGIN TRY

        if @action = 'SyncChildren'
        begin
            declare @parents as app_pkids; insert into @parents select id from dbo.objs_buffer(@mol_id, 'mfr')
            exec mfr_docs_sync @mol_id = @mol_id, @parents = @parents
        end

        else if @action = 'ImportContents'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            insert into @docs select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfr'
            exec mfr_replicate @mol_id = @mol_id, @docs = @docs, @channel = 'ImportContents'
        end

        else if @action = 'BuildContentsFromPdm'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            insert into @docs select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfr'
            if exists(
                select 1 from mfr_drafts d
                    join @docs i on i.id = d.mfr_doc_id
                    join (
                        select draft_id, c_rows = count(*)
                        from mfr_drafts where is_deleted = 0
                        group by draft_id
                    ) dd on dd.draft_id = d.draft_id
                where d.is_deleted = 0
                    and dd.c_rows > 1
                )
                raiserror('Есть заказы с непустым составом изделия. Операция формирования отменена.', 16, 1)

            exec mfr_docs_from_pdm @mol_id = @mol_id, @docs = @docs
        end

        else if @action = 'BuildContents'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            insert into @docs select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfr'
            exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs
        end

        else if @action = 'BuildMilestones'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            delete x from sdocs_mfr_milestones x
                join @buffer i on i.id = x.doc_id
                join (
                    select doc_id from sdocs_products
                    group by doc_id having count(*) = 1
                ) sp on sp.doc_id = x.doc_id
            where not exists(select 1 from sdocs_products where doc_id = sp.doc_id and product_id = x.product_id)

            insert into sdocs_mfr_milestones(doc_id, product_id, attr_id, ratio, ratio_value)
            select distinct x.mfr_doc_id, c.product_id, x.milestone_id, 0, 0
            from sdocs_mfr_opers x			
                join @buffer i on i.id = x.mfr_doc_id
                join sdocs_mfr_contents c on c.content_id = x.content_id
            where x.milestone_id is not null
                and not exists(select 1 from sdocs_mfr_milestones where doc_id = x.mfr_doc_id and attr_id = x.milestone_id)

            exec mfr_milestones_calc @docs = @buffer
        end

        else if @action = 'ImportMilestones'
        begin
            declare @product_attr_id int = (select top 1 attr_id from mfr_attrs where name like '%Готовая продукция%')

            exec sys_set_triggers 0
                -- очищаем переделы выбранных заказов
                    update sdocs_mfr_opers set milestone_id = null
                    where mfr_doc_id in (select id from @buffer);
                
                -- наследуем от других заказов
                    declare @map table(mfr_doc_id int, product_id int, src_doc_id int)
                    insert into @map(mfr_doc_id, product_id)
                    select sp.doc_id, sp.product_id
                    from sdocs_products sp
                        join @buffer i on i.id = sp.doc_id

                    update x set src_doc_id = xx.mfr_doc_id
                    from @map x
                        join (
                            select o.product_id, max(mfr_doc_id) as mfr_doc_id
                            from sdocs_mfr_opers o
                                join sdocs mfr on mfr.doc_id = o.mfr_doc_id and mfr.template_name is not null
                            where o.milestone_id != @product_attr_id
                            group by o.product_id
                        ) xx on xx.product_id = x.product_id

                    declare @milestones table(
                        src_doc_id int, product_id int, place_id int, item_id int, milestone_id int
                        index ix (src_doc_id, product_id, place_id, item_id)
                        );
                        
                        -- Тиражирование переделов по шаблону происходит по совокупности признаков
                        -- “Участок(id)+Деталь(id)+Последняя операция” из заказа, который отмечен как шаблон по готовой продукции.
                        insert into @milestones(src_doc_id, product_id, place_id, item_id, milestone_id)
                        select m.src_doc_id, c.product_id, o.place_id, c.item_id, max(o.milestone_id)
                        from sdocs_mfr_contents c
                            join sdocs_mfr_opers o on o.content_id = c.content_id
                            join @map m on m.src_doc_id = c.mfr_doc_id
                        where o.milestone_id is not null
                        group by m.src_doc_id, c.product_id, o.place_id, c.item_id;

                    declare @milestones_new table(
                        mfr_doc_id int, product_id int, place_id int, item_id int, milestone_id int, oper_number int,
                        index ix (mfr_doc_id, product_id, place_id, item_id)
                        );

                    insert into @milestones_new(mfr_doc_id, product_id, place_id, item_id, milestone_id)
                    select m.mfr_doc_id, x.product_id, x.place_id, x.item_id, x.milestone_id
                    from @milestones x
                        join @map m on m.src_doc_id = x.src_doc_id;

                    update x set oper_number = xx.oper_number
                    from @milestones_new x
                        join (
                            select xx.mfr_doc_id, xx.product_id, xx.place_id, xx.item_id, max(x.number) as oper_number
                            from sdocs_mfr_opers x
                                join sdocs_mfr_contents c on c.content_id = x.content_id
                                join @milestones_new xx on xx.mfr_doc_id = x.mfr_doc_id
                                    and xx.product_id = c.product_id
                                    and xx.place_id = x.place_id
                                    and xx.item_id = c.item_id
                            group by xx.mfr_doc_id, xx.product_id, xx.place_id, xx.item_id
                        ) xx on xx.mfr_doc_id = x.mfr_doc_id
                                and xx.product_id = x.product_id
                                and xx.place_id = x.place_id
                                and xx.item_id = x.item_id;

                    update x set milestone_id = xx.milestone_id
                    from sdocs_mfr_opers x
                        join sdocs_mfr_contents c on c.content_id = x.content_id
                        join @milestones_new xx on xx.mfr_doc_id = x.mfr_doc_id
                            and xx.product_id = c.product_id
                            and xx.place_id = x.place_id
                            and xx.item_id = c.item_id
                            and xx.oper_number = x.number
                    where xx.oper_number is not null;

                exec sys_set_triggers 1
        end

        else if @action = 'PinPlan'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            update ms set d_to_plan_hand = d_to_plan
            from mfr_sdocs_milestones ms
                join @buffer i on i.id = ms.doc_id
                join mfr_attrs a on a.attr_id = ms.attr_id
            where a.name like '%Готовая продукция%'			
        end

        else if @action = 'UnpinPlan'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            update ms set d_to_plan_hand = null
            from mfr_sdocs_milestones ms
                join @buffer i on i.id = ms.doc_id
                join mfr_attrs a on a.attr_id = ms.attr_id
            where a.name like '%Готовая продукция%'			
        end

        else if @action = 'BindStatus'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            update x set status_id = @status_id
            from mfr_sdocs x
                join @buffer i on i.id = x.doc_id
        end

        else if @action = 'BindPriority'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            update x set priority_id = @priority_id
            from mfr_sdocs x
                join @buffer i on i.id = x.doc_id
        end

        else if @action = 'ReadPrices'
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            EXEC SYS_SET_TRIGGERS 0
                
                update x set
                    unit_name = pr.unit_name,
                    item_price0 = pr.price
                from mfr_drafts x
                    join (
                        select x.draft_id, 
                            c.unit_name,
                            price = pr.price 
                                / 
                                case 
                                    when u.name = c.unit_name then 1.0 
                                    else nullif(coalesce(uk.koef, dbo.product_ukoef(u.name, c.unit_name), 1), 0)
                                end
                        from mfr_drafts x
                            join sdocs_mfr_contents c on c.draft_id = x.draft_id
                            join @buffer i on i.id = x.mfr_doc_id
                            join mfr_items_prices pr on pr.product_id = x.item_id
                                join products_units u on u.unit_id = pr.unit_id
                                left join products_ukoefs uk on uk.product_id = pr.product_id and uk.unit_from = u.name and uk.unit_to = c.unit_name
                        where c.is_buy = 1 and x.is_deleted = 0
                    ) pr on pr.draft_id = x.draft_id
                where isnull(x.item_price0,0) != pr.price

                update c set 
                    item_price0 = d.item_price0
                        / 
                        case 
                            when d.unit_name = c.unit_name then 1.0 
                            else nullif(coalesce(uk.koef, dbo.product_ukoef(d.unit_name, c.unit_name), 1), 0)
                        end
                from sdocs_mfr_contents c
                    join @buffer i on i.id = c.mfr_doc_id
                    join mfr_drafts d on d.draft_id = c.draft_id
                    left join products_ukoefs uk on uk.product_id = c.item_id and uk.unit_from = d.unit_name and uk.unit_to = c.unit_name
                where c.is_buy = 1

            EXEC SYS_SET_TRIGGERS 1
        end

    END TRY
    BEGIN CATCH
        declare @errtry varchar(max) = error_message()
        raiserror (@errtry, 16, 3)
    END CATCH

    -- trace end
        exec tracer_close @tid

end
GO
exec mfr_docs_buffer_action 1000, 'ImportMilestones'