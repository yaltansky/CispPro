if object_id('buyorders_create_orders') is not null drop proc buyorders_create_orders
go
create proc buyorders_create_orders
	@mol_id int,
	@subject_id int,
	@consignee_id int = null,
	@ignore_stoplist bit = 1,
	@groupby_manager bit = 1,
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

	declare @today datetime = dbo.today()	

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
        declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			'subject_id = ', @subject_id
			)
        exec tracer_log @tid, @tid_msg      

    BEGIN TRY
    BEGIN TRANSACTION
        exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name

        declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
        declare @buffer as app_pkids
            if @queue_id is null
                insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
            else
                insert into @buffer select obj_id from queues_objs
                where queue_id = @queue_id and obj_type = 'mfc'

        if @groupby_manager = 1
            and exists(
                select 1
                from mfr_sdocs_contents c 
                    join @buffer buf on buf.id = c.content_id
                where c.supplier_id is null
                    or c.manager_id is null
            ) 
        begin
            raiserror('Есть материальная потребность без поставщика и/или менеджера закупок. Воспользуйтесь фильтром для поиска и устраните проблему.', 16, 1)
        end

        declare @products table(
            product_id int primary key,
            price_pure float
            )
            insert into @products(product_id, price_pure)
            select c.item_id, min(isnull(c.item_price0/1.2, pr.price_pure))
            from mfr_sdocs_contents c 
                join @buffer buf on buf.id = c.content_id
                left join mfr_items_prices pr on pr.product_id = c.item_id
            group by c.item_id

        declare @docs table(
            doc_id int, agent_id int, mol_id int,
            primary key(agent_id, mol_id)
            )

        declare @details table(
            agent_id int,
            mol_id int,
            product_id int,
            mfr_number varchar(50),
            unit_id int,
            quantity float,
            plan_q float,
            due_date date,
            price_pure float,
            nds_ratio decimal(5,4),
            index ix (agent_id,mol_id,product_id)
            )

        -- fake agent
        declare @agent_id int = (select top 1 agent_id from agents where name = 'контрагент не указан')
        if @agent_id is null
        begin
            insert into agents(name) values ('Контрагент не указан')
            set @agent_id = (select agent_id from agents where name = 'контрагент не указан')
        end

        declare @contents table(content_id int primary key, unit_name varchar(20), order_q float)
        insert into @contents(content_id, unit_name, order_q)
        select id_mfr, r.unit_name, sum(q_mfr)
        from mfr_r_provides r
            join sdocs_mfr_contents c on c.content_id = r.id_mfr
            join @buffer buf on buf.id = r.id_mfr
        where isnull(q_order, 0) = 0 and isnull(q_invoice, 0) = 0 and isnull(q_ship, 0) = 0 and isnull(q_job, 0) = 0
        group by r.id_mfr, r.unit_name 
        having sum(q_mfr) > 0

        insert into @details(
            agent_id, mol_id, 
            mfr_number, product_id, unit_id,
            quantity, plan_q, due_date,
            nds_ratio, price_pure
            )
        select
            case when @groupby_manager = 1 then c.supplier_id else @agent_id end, 
            case when @groupby_manager = 1 then c.manager_id else @mol_id end, 
            mfr.number, c.item_id, u.unit_id, 
            sum(cc.order_q), sum(cc.order_q), min(c.opers_to),
            0.2, min(p.price_pure)
        from mfr_sdocs_contents c 
            join @contents cc on cc.content_id = c.content_id
                join products_units u on u.name = cc.unit_name
            join sdocs mfr on mfr.doc_id = c.mfr_doc_id
            left join @products p on p.product_id = c.item_id
        group by 
            case when @groupby_manager = 1 then c.supplier_id else @agent_id end,
            case when @groupby_manager = 1 then c.manager_id else @mol_id end,
            mfr.number, c.item_id, u.unit_id

        if exists(select 1 from @details)
        begin
            if @consignee_id is null
                select @consignee_id = pred_id from subjects where subject_id = @subject_id

            -- sdocs
                insert into sdocs(
                    subject_id, type_id, status_id, d_doc, agent_id, consignee_id, mol_id, ccy_id, add_mol_id, add_date
                    )
                    output inserted.doc_id, inserted.agent_id, inserted.mol_id into @docs
                select 
                    @subject_id, 
                    18, -- заявка
                    10, -- статус "Исполнение"
                    @today, agent_id, @consignee_id, mol_id, 'RUR',
                    @mol_id, getdate()
                from @details
                group by agent_id, mol_id

                update x set 
                    number = concat(s.short_name, '/ЗВК/', x.doc_id),
                    refkey = concat('/finance/buyorders/', doc_id) 
                from sdocs x
                    join subjects s on s.subject_id = x.subject_id
                where x.doc_id in (select doc_id from @docs)
                
                print concat('created ', @@rowcount, ' buyorders')

            -- sdocs_products
                insert into sdocs_products(
                    doc_id, mfr_number, product_id, unit_id, quantity, plan_q, due_date, price_pure, nds_ratio
                    )
                select
                    d.doc_id, x.mfr_number, x.product_id, x.unit_id, x.quantity, x.plan_q, x.due_date, x.price_pure, x.nds_ratio
                from @details x
                    join @docs d on d.agent_id = x.agent_id and d.mol_id = x.mol_id

            -- lock status
            	update c set status_id = 10
            	from mfr_sdocs_contents c
            		join @contents cc on cc.content_id = c.content_id

            -- results
                delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'BUYORDER'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select @buffer_id, 'BUYORDER', doc_id, @mol_id from @docs
        end

        else
            print 'creating buyorders: nothing to do'

    COMMIT TRANSACTION
        -- recalc
        if exists(select 1 from @details)
        begin
            declare @items as app_pkids; insert into @items select distinct product_id from @details
            exec mfr_provides_calc @mol_id = @mol_id, @items = @items, @queue_id = @queue_id
        end

    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        declare @err varchar(max); set @err = error_message()
        raiserror (@err, 16, 3)
    END CATCH -- TRANSACTION

end
go
