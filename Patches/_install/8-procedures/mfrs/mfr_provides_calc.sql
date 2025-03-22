if object_id('mfr_provides_calc') is not null drop proc mfr_provides_calc
go
create proc mfr_provides_calc
	@mol_id int = null,
	@items app_pkids readonly,
	@queue_id uniqueidentifier = null
as
begin
	set nocount on;

	-- buffer
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
		delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'P'

		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'P', id, @mol_id
		from @items

		declare @thread_id varchar(32) = (select thread_id from queues where queue_id = @queue_id)

	-- append
		declare @qid uniqueidentifier = newid()
		exec queue_append
			@queue_id = @qid,
			@mol_id = @mol_id,
			@thread_id = @thread_id,
			@name = 'Пересчёт обеспечения материалов (**)',
			@sql_cmd = 'RMQ.mfr_provides_calc_items',
			@use_rmq = 1

	-- parent_id
		update queues set parent_id = (select id from queues where queue_id = @queue_id)
		where queue_id = @qid
end
go
-- helper: get data
create proc mfr_provides_calc;2
	@queue_id uniqueidentifier = null,
	@archive_date date = null,
	@filter_items bit = 0,
    @debug_item_id int = null,
	@debug bit = 0
as
begin
    set nocount on;

	exec mfr_provides_calc;10 -- prepare

	-- #fifo
		select top 0
			MFR_NUMBER = CAST(NULL AS VARCHAR(100)),
            PRINCIPAL_DOGOVOR_ID = CAST(NULL AS INT),
			SORT_ID = CAST(NULL AS INT),
			CANCEL_REASON_ID = CAST(NULL AS INT),
			ID_JOB_STATUS = CAST(NULL AS INT),
			ID_SHIP_INVOICE = CAST(NULL AS INT),
            ID_SHIP_HAS_INVOICE = CAST(NULL AS INT),
			*
		into #fifo from mfr_r_provides

	declare @calc_archive bit = 0

	-- #docs
		create table #docs(id int primary key)
		if @archive_date is null
		begin
			if not exists(select 1 from mfr_r_provides_archive)
			begin
				set @archive_date = '1900-01-01'
				insert into #docs select doc_id from mfr_sdocs where status_id >= 0
			end
			else begin
				set @archive_date = (select top 1 archive_date from mfr_r_provides_archive)
				insert into #docs select doc_id from mfr_sdocs where status_id >= 0 
                    and isnull(d_issue, @archive_date) >= @archive_date
			end
		end
		
		else begin
			set @calc_archive = 1
			insert into #docs select doc_id from mfr_sdocs where status_id >= 0 and d_issue < @archive_date
			if object_id('mfr_r_provides_archive') is not null and @debug = 0 truncate table mfr_r_provides_archive
		end
	-- #items
		create table #items(id int primary key)
		insert into #items exec mfr_provides_calc;90 @queue_id = @queue_id

        if @debug_item_id is not null
        begin
            delete from #items; insert into #items select @debug_item_id
            set @filter_items = 1
            set @debug = 1
        end

		if @debug = 0
		begin
			if @filter_items = 1
				delete x from mfr_r_provides x
					join #items i on i.id = x.item_id
			else
				truncate table mfr_r_provides
		end
	-- /*** DEBUG ***/
        -- DELETE FROM #ITEMS; INSERT INTO #ITEMS SELECT 5700
		-- SET @FILTER_ITEMS = 1

	print 'read prices (if any)'
		exec sys_set_triggers 0
            if isnull(@filter_items,0) = 0 and @calc_archive = 0
                exec mfr_items_prices_calc 1

			update c set
				item_price0 = cc.calc_price
			from sdocs_mfr_contents c
                join (
                    select c.content_id, 
                        calc_price = pr.price 
                            / 
                            case 
                                when c.unit_name = u.name then 1.0 
                                else nullif(coalesce(uk.koef, dbo.product_ukoef(u.name, c.unit_name), 1), 0)
                            end
                    from sdocs_mfr_contents c
                        join #docs i on i.id = c.mfr_doc_id
                        join mfr_items_prices pr on pr.product_id = c.item_id
                            join products_units u on u.unit_id = pr.unit_id
                            left join products_ukoefs uk on uk.product_id = pr.product_id and uk.unit_from = u.name and uk.unit_to = c.unit_name
                ) cc on cc.content_id = c.content_id
			where isnull(c.item_price0, 0) != cc.calc_price
				and (@filter_items = 0 or c.item_id in (select id from #items))
			
		exec sys_set_triggers 1
    print 'материальная потребность'
        declare @d_restrict date = dateadd(d, 1, dbo.today())
    
		insert into #fifo(
            acc_register_id,
			sort_id, mfr_doc_id, item_id, unit_name, id_mfr, cancel_reason_id, d_mfr, d_mfr_to, q_mfr, price, slice
			)
		select 
            isnull(x.acc_register_id, 0),
			row_number() over (order by 
                isnull(ext_type_id, 0),
                case
                    when d_mfr_to < @d_restrict then x.priority_id
                    else 1000
                end,
                d_mfr_to, id_mfr
                ),
			mfr_doc_id, item_id, unit_name, id_mfr, cancel_reason_id, d_mfr, d_mfr_to, q_mfr, item_price0, 'mfr'
		from (
			select
				mfr.ext_type_id,
                mfr.acc_register_id,
				c.mfr_doc_id,
                mfr.priority_id,
				c.cancel_reason_id,
				c.item_id,
				c.unit_name,
				id_mfr = c.content_id,
				d_mfr = c.opers_from_plan,
				d_mfr_to = c.opers_to_plan,
				q_mfr = c.q_brutto_product,
				c.item_price0
			from sdocs_mfr_contents c with(nolock)
				join #docs i on i.id = c.mfr_doc_id
				join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id
			where c.is_buy = 1
                and mfr.plan_id is not null
				and isnull(c.cancel_reason_id, 20) = 20
				and (@filter_items = 0 or c.item_id in (select id from #items))
				and c.opers_to_plan is not null

			union all
			select 
				mfr.ext_type_id,
                a.acc_register_id,
				mfr_doc_id,
				mfr.priority_id,
                null, -- cancel_reason_id
				item_id,
				unit_name,
				id_mfr, d_mfr, d_mfr_to, q_mfr, a.price
			from mfr_r_provides_archive a
                join mfr_sdocs mfr on mfr.doc_id = a.mfr_doc_id
			where archive = 0 and q_mfr > 0
				and (@filter_items = 0 or item_id in (select id from #items))
			) x
		where x.q_mfr > 0
	print 'услуги кооперации'
		insert into #fifo(
            acc_register_id,
			sort_id, mfr_doc_id, item_id, unit_name, id_mfr, d_mfr, d_mfr_to, q_mfr, price, slice
			)
		select 
            isnull(x.acc_register_id, 0),
			row_number() over (order by x.priority_id, d_mfr_to, id_mfr),
			mfr_doc_id, item_id, unit_name, id_mfr, d_mfr, d_mfr_to, q_mfr, item_price0, 'coop'
		from (
			select 
                acc_register_id, mfr_doc_id, priority_id, id_mfr, item_id, unit_name,
                d_mfr = min(d_mfr),
                d_mfr_to = max(d_mfr_to),
                q_mfr = sum(q_mfr),
                item_price0 = sum(item_price0 * q_mfr) / nullif(sum(q_mfr), 0)
            from (
                select
                    mfr.acc_register_id,
                    c.mfr_doc_id,
                    mfr.priority_id,
                    cp.item_id,
                    unit_name = u.name,
                    id_mfr = c.content_id,
                    d_mfr = o.d_from_plan,
                    d_mfr_to = o.d_to_plan,
                    q_mfr = cp.quantity * c.q_brutto_product,
                    item_price0 = cp.sum_price
                from sdocs_mfr_contents c with(nolock)
                    join #docs i on i.id = c.mfr_doc_id
                    join mfr_sdocs mfr with(nolock) on mfr.doc_id = c.mfr_doc_id
                    join sdocs_mfr_opers o with(nolock) on o.content_id = c.content_id
                        join mfr_drafts_opers oo with(nolock) on oo.draft_id = c.draft_id and oo.number = o.number
                            join mfr_drafts_opers_coops cp with(nolock) on cp.oper_id = oo.oper_id
                                left join products_units u on u.unit_id = cp.unit_id
                where c.is_buy = 0
                ) x
                group by acc_register_id, mfr_doc_id, priority_id, id_mfr, item_id, unit_name
			) x
		where x.q_mfr > 0
            and (@filter_items = 0 or x.item_id in (select id from #items))
	print 'заявки на поставку'
		insert into #fifo(
			acc_register_id,
			sort_id, mfr_doc_id, mfr_number, item_id, unit_name, id_order, d_order, d_delivery, q_order
			)
		select 
			isnull(u.acc_register_id, 0),
			row_number() over (order by d_doc, doc_id),
			mfr_doc_id, mfr_number, product_id, unit_name, doc_id, d_doc, d_delivery, quantity
		from (
			select 
				mfr.acc_register_id,
				mfr_doc_id = mfr.doc_id,
                sp.mfr_number,
				mfr.d_ship,
				sp.product_id,
				unit_name = u.name,
				sd.doc_id, 
				d_doc = isnull(sp.due_date, sd.d_doc),
				sd.d_delivery, sp.quantity
			from supply_buyorders sd with(nolock)
				join sdocs_products sp with(nolock) on sp.doc_id = sd.doc_id
					join mfr_sdocs mfr with(nolock) on mfr.number = sp.mfr_number
						join #docs d on d.id = mfr.doc_id
					left join products_units u on u.unit_id = sp.unit_id
			where sd.status_id >= 0
				and sp.product_id is not null
				and sp.quantity > 0
				and (
					(@calc_archive = 1 and sd.d_doc < @archive_date)
					or (@calc_archive = 0 and sd.d_doc >= @archive_date)
				)

			union all
			select 
				acc_register_id,
				mfr_doc_id,
                null, -- mfr_number
				d_order,
				item_id,
				unit_name,
				id_order, 
				min(d_order), 
				min(d_delivery), sum(q_order)
			from mfr_r_provides_archive
			where archive = 0 and q_order > 0
				and (@filter_items = 0 or item_id in (select id from #items))
			group by 
				acc_register_id, mfr_doc_id, d_order, item_id, unit_name, id_order
			) u
		where (@filter_items = 0 or product_id in (select id from #items))
    print 'счета поставщиков'
		insert into #fifo(
			acc_register_id, principal_dogovor_id,
			sort_id, mfr_doc_id, mfr_number, item_id, unit_name, id_invoice, agent_id, d_invoice, d_delivery, q_invoice
			)
		select 
			isnull(u.acc_register_id, 0),
            isnull(u.principal_dogovor_id, 0),
			row_number() over (order by d_doc, doc_id),
			mfr_doc_id, mfr_number, product_id, unit_name,
			doc_id, agent_id, d_doc, d_delivery, quantity
		from (
			select 
				case when mfr.doc_id is not null then mfr.acc_register_id else sd.acc_register_id end as acc_register_id,
                sd.principal_dogovor_id,
				mfr_doc_id = isnull(mfr.doc_id, 0),
                sp.mfr_number,
				d_ship = isnull(mfr.d_ship, sd.d_delivery),
				sp.product_id,
				unit_name = u.name,
				sd.doc_id, sd.agent_id, sd.d_doc, sd.d_delivery, sp.quantity
			from supply_invoices sd with(nolock)
				join (
                    select 
                        sp.doc_id, sp.product_id, 
                        coalesce(spd.mfr_number, sp.mfr_number) as mfr_number,
                        coalesce(spd.quantity, sp.quantity) as quantity, 
                        sp.unit_id
                    from sdocs_products sp with(nolock) 
                        left join sdocs_products_details spd with(nolock) on spd.doc_id = sp.doc_id and spd.detail_id = sp.detail_id
                ) sp on sp.doc_id = sd.doc_id
					left join mfr_sdocs mfr with(nolock) on mfr.number = sp.mfr_number
					left join products_units u on u.unit_id = sp.unit_id
			where sd.status_id > 0
				and sp.product_id is not null
				and sp.quantity > 0
				and (
					(@calc_archive = 1 and sd.d_doc < @archive_date)
					or (@calc_archive = 0 and sd.d_doc >= @archive_date)
				)

			union all
			select 
				a.acc_register_id,
                sd.principal_dogovor_id,
				mfr_doc_id = isnull(a.mfr_doc_id_invoice, 0),
                null, -- mfr_number
				a.d_invoice,
				a.item_id,
				a.unit_name,
				a.id_invoice, a.agent_id, min(a.d_invoice), min(a.d_delivery), sum(a.q_invoice)
			from mfr_r_provides_archive a
                join sdocs sd on sd.doc_id = a.id_invoice
			where a.archive = 0 and a.q_invoice > 0
				and (@filter_items = 0 or a.item_id in (select id from #items))
			group by 
				a.acc_register_id, sd.principal_dogovor_id, isnull(a.mfr_doc_id_invoice, 0), a.d_invoice, a.item_id, a.unit_name, a.id_invoice, a.agent_id
			) u
		where (@filter_items = 0 or product_id in (select id from #items))
	print 'поступления на склад'
		insert into #fifo(
			acc_register_id, principal_dogovor_id,
			sort_id, mfr_doc_id, mfr_number, item_id, unit_name, d_ship, id_ship, agent_id, id_ship_invoice, id_ship_has_invoice, q_ship, price_ship, slice
			)
		select 
			isnull(u.acc_register_id, 0),
			isnull(u.principal_dogovor_id, 0),
			row_number() over (order by d_ship, id_ship),
			mfr_doc_id, mfr_number, item_id, unit_name, d_ship, id_ship, agent_id, invoice_id, has_invoice, sum(quantity), min(price), 'ship'
		from (
			select 
				case when mfr.doc_id is not null then mfr.acc_register_id else sd.acc_register_id end as acc_register_id,
				sd.principal_dogovor_id,
				isnull(mfr.doc_id,0) as mfr_doc_id,
                sp.mfr_number,
				sp.product_id as item_id,
				sd.d_doc as d_ship,
				sd.doc_id as id_ship,
				sd.agent_id,
				sd.invoice_id,
                sd.has_invoice,
				u.name as unit_name,
				sp.quantity,
				sp.price * isnull(cr.rate,1) as price
			from sdocs sd with(nolock)
				join (
                    select 
                        sp.doc_id, sp.product_id, 
                        coalesce(spd.mfr_number, sp.mfr_number) as mfr_number,
                        coalesce(spd.quantity, sp.quantity) as quantity,
                        sp.unit_id,
                        sp.price
                    from sdocs_products sp with(nolock) 
                        left join sdocs_products_details spd with(nolock) on spd.doc_id = sp.doc_id and spd.detail_id = sp.detail_id
                ) sp on sp.doc_id = sd.doc_id
					left join products_units u on u.unit_id = sp.unit_id
					left join mfr_sdocs mfr with(nolock) on mfr.number = sp.mfr_number
                left join ccy_rates_cross cr on cr.d_doc = sd.d_doc and cr.from_ccy_id = sd.ccy_id and cr.to_ccy_id = 'rur'
			where sd.type_id in (9, 100)
				and sd.status_id = 100
				and sp.quantity > 0
				and sp.product_id is not null
				and (
					(@calc_archive = 1 and sd.d_doc < @archive_date)
					or (@calc_archive = 0 and sd.d_doc >= @archive_date)
				)

			union all
			select 
				r.acc_register_id,
				sd.principal_dogovor_id,
				mfr_doc_id = isnull(r.mfr_doc_id_ship, 0),
                null, -- mfr_number
				r.item_id,
				r.d_ship,
				r.id_ship,
				r.agent_id,
				sd.invoice_id,
                sd.has_invoice,
				r.unit_name,
				r.q_ship,
				r.price_ship
			from mfr_r_provides_archive r
                join sdocs sd on sd.doc_id = r.id_ship
			where archive = 0 and q_ship > 0
				and (@filter_items = 0 or item_id in (select id from #items))
			) u		
		where (@filter_items = 0 or item_id in (select id from #items))
		group by acc_register_id, principal_dogovor_id, mfr_doc_id, mfr_number, item_id, unit_name, d_ship, id_ship, agent_id, invoice_id, has_invoice
	print 'учёт перераспределения'
		insert into #fifo(
			acc_register_id,
			sort_id, mfr_doc_id, mfr_number, mfr_to_doc_id, item_id, d_ship, id_ship, unit_name, q_distrib, slice
			)
		select 
			isnull(u.acc_register_id, 0),
			row_number() over (order by d_ship, id_ship),
			mfr_doc_id, mfr_number, mfr_to_doc_id, item_id, d_ship, id_ship, unit_name, quantity, 'distrib'
		from (
			select
				mfr.acc_register_id,
				mfr_doc_id = mfr.doc_id,
                sp.mfr_number,
				mfr_to_doc_id = mfr2.doc_id,
				item_id = sp.product_id,
				d_ship = sd.d_doc, 
				id_ship = sd.doc_id,
				unit_name = u.name,
				sp.quantity
			from sdocs sd with(nolock)
				join sdocs_products sp with(nolock) on sp.doc_id = sd.doc_id
					join mfr_sdocs mfr with(nolock) on mfr.number = sp.mfr_number_from
					join mfr_sdocs mfr2 with(nolock) on mfr2.number = sp.mfr_number
					left join products_units u on u.unit_id = sp.unit_id
			where sd.type_id = 13
				and sd.status_id = 100
				and sp.quantity > 0
				and (
					(@calc_archive = 1 and sd.d_doc < @archive_date)
					or (@calc_archive = 0 and sd.d_doc >= @archive_date)
				)

			union all
			select 
				acc_register_id,
				mfr_doc_id = 0,
                null, -- mfr_number
				mfr_to_doc_id,
				item_id,
				min(d_ship),
				id_ship,
				unit_name,
				sum(q_distrib)
			from mfr_r_provides_archive
			where archive = 0 and q_distrib > 0 and isnull(q_job,0) = 0
				and (@filter_items = 0 or item_id in (select id from #items))
			group by acc_register_id, mfr_doc_id, mfr_to_doc_id, item_id, id_ship, unit_name
			) u
		where (@filter_items = 0 or item_id in (select id from #items))
	print 'выдача в производство, продажа со склада'
		insert into #fifo(
			acc_register_id, principal_dogovor_id,
			sort_id, mfr_doc_id, mfr_number, item_id, d_job, id_job, id_job_status, unit_name, q_job, slice
			)
		select 
			isnull(u.acc_register_id, 0),
			isnull(u.principal_dogovor_id, 0),
			row_number() over (order by d_doc, doc_id),
			mfr_doc_id, mfr_number, item_id, d_doc, doc_id, status_id, unit_name, quantity, 'job'
		from (
			select 
				case when mfr.doc_id is not null then mfr.acc_register_id else sd.acc_register_id end as acc_register_id,
				sd.principal_dogovor_id,
				sort_id = sd.doc_id,
				mfr_doc_id = isnull(mfr.doc_id, 0),
                sp.mfr_number,
				item_id = sp.product_id,
				sd.d_doc,
				sd.doc_id,
				sd.status_id,
                sd.agent_id,
				unit_name = u.name,
				quantity = abs(sp.quantity)
			from sdocs_products sp
				join sdocs sd on sd.doc_id = sp.doc_id
				left join mfr_sdocs mfr on mfr.number = sp.mfr_number
				left join products_units u on u.unit_id = sp.unit_id
			where sd.type_id in (12, 14, 100)
				and sd.status_id >= 0
				and (
                    (sd.type_id = 100 and sp.quantity < 0) -- недостача инвентаризации
                    or (sd.type_id != 100 and sp.quantity > 0)
                    )
				and (
					(@calc_archive = 1 and (sd.d_doc < @archive_date and sd.status_id = 100))
					or (@calc_archive = 0 and (sd.d_doc >= @archive_date or sd.status_id != 100))
				)
			
			union all
			select 
				a.acc_register_id,
                sd.principal_dogovor_id,
				a.id_job,
				a.mfr_doc_id,
                null, -- mfr_number
				a.item_id,
				min(a.d_job),
				a.id_job,
				status_id = 100,
                a.agent_id,
				a.unit_name,
				sum(a.q_job)
			from mfr_r_provides_archive a
                join sdocs sd on sd.doc_id = a.id_job
			where a.archive = 0 and a.q_job > 0
				and (@filter_items = 0 or a.item_id in (select id from #items))
			group by a.acc_register_id, sd.principal_dogovor_id, a.mfr_doc_id, a.item_id, a.id_job, a.agent_id, a.unit_name
			) u
		where u.item_id is not null
			and (@filter_items = 0 or item_id in (select id from #items))
	print 'возврат из производства'
		insert into #fifo(
			acc_register_id,
			sort_id, mfr_doc_id, mfr_number, item_id, d_return, id_return, unit_name, q_return, slice
			)
		select 
			isnull(u.acc_register_id, 0),
			row_number() over (order by d_doc, doc_id),
			mfr_doc_id, mfr_number, item_id, d_doc, doc_id, unit_name, quantity, 'return'
		from (
			select 
				case when mfr.doc_id is not null then mfr.acc_register_id else sd.acc_register_id end as acc_register_id,
				sort_id = sd.doc_id,
				mfr_doc_id = isnull(mfr.doc_id, 0),
                sp.mfr_number,
				item_id = sp.product_id,
				sd.d_doc,
				sd.doc_id,
				unit_name = u.name,
				sp.quantity
			from sdocs_products sp
				join sdocs sd on sd.doc_id = sp.doc_id
				left join mfr_sdocs mfr on mfr.number = sp.mfr_number
				left join products_units u on u.unit_id = sp.unit_id
			where sd.type_id = 19
				and sd.status_id >= 0
				and sp.quantity > 0
				and (
					(@calc_archive = 1 and sd.d_doc < @archive_date)
					or (@calc_archive = 0 and sd.d_doc >= @archive_date)
				)
			
			union all
			select 
				acc_register_id,
				id_return,
				mfr_doc_id,
                null, -- mfr_number
				item_id,
				min(d_return),
				id_return,
				unit_name,
				sum(q_return)
			from mfr_r_provides_archive
			where archive = 0 and q_return > 0
				and (@filter_items = 0 or item_id in (select id from #items))
			group by acc_register_id, mfr_doc_id, item_id, id_return, unit_name
			) u
		where u.item_id is not null
			and (@filter_items = 0 or item_id in (select id from #items))

	;create index ix_fifo on #fifo (item_id, sort_id)
	
	-- units
		create table #products(product_id int primary key, unit_name varchar(20))
			-- default unit_name
			insert into #products(product_id, unit_name)
			select item_id, min(unit_name) from #fifo group by item_id

			-- override by products
			update x set unit_name = u.name
			from #products x
				join products p on p.product_id = x.product_id
				join products_units u on u.unit_id = p.unit_id

		-- convert units
		declare @koef float

		update x set 
			@koef = coalesce(uk.koef, dbo.product_ukoef(x.unit_name, p.unit_name), 1),
			unit_name = p.unit_name,
			q_mfr = x.q_mfr * @koef,
			q_order = x.q_order * @koef,
			q_invoice = x.q_invoice * @koef,
			q_ship = x.q_ship * @koef,
			q_job = x.q_job * @koef,
			price = price / nullif(@koef,0),
			price_ship = price_ship / nullif(@koef,0)
		from #fifo x					
			join #products p on p.product_id = x.item_id
			left join products_ukoefs uk on uk.product_id = x.item_id and uk.unit_from = x.unit_name and uk.unit_to = p.unit_name
		where x.unit_name != p.unit_name
	
    -- result
		if @debug = 1
			-- select R = sum(q_mfr), INV = sum(q_invoice), S = sum(q_ship), J = sum(q_job), LZK = sum(q_lzk), D = sum(q_distrib)from #fifo 
            select * from #fifo where id_ship = 37922358
		else
			select * from #fifo
            where isnull(item_id,0) != 0 
			order by item_id, sort_id

	final:
		exec drop_temp_table '#products,#fifo'
end
go
-- helper: prepare
create proc mfr_provides_calc;10 
as 
begin
	set nocount on;

	IF OBJECT_ID('MFR_R_PROVIDES_ARCHIVE') IS NULL
		SELECT TOP 0 *, 
			ARCHIVE = CAST(0 AS BIT),
			ARCHIVE_DATE = CAST(NULL AS DATE),
			ARCHIVE_USER = CAST(NULL AS INT)
		INTO MFR_R_PROVIDES_ARCHIVE
		FROM MFR_R_PROVIDES
end
go
-- helper: apply @queue_id
create proc mfr_provides_calc;90
	@queue_id uniqueidentifier
as
begin
	declare @items app_pkids

	if exists(select 1 from queues_objs where queue_id = @queue_id and obj_type = 'MFC')
	begin
		delete from queues_objs where queue_id = @queue_id and obj_type = 'P'
		
		insert into queues_objs(queue_id, obj_type, obj_id)
		select distinct @queue_id, 'P', item_id from sdocs_mfr_contents c
			join queues_objs q on q.obj_id = c.content_id
		where queue_id = @queue_id and q.obj_type = 'MFC'
	end
	
	insert into @items select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'p'
	select id from @items
end
go
-- helper: calc statuses
create proc mfr_provides_calc;100
	@queue_id uniqueidentifier,
	@archive_date date = null,
	@filter_items bit = 0,
	@trace bit = 0
as
begin
	set nocount on;

    DECLARE @PRECISION FLOAT = 1E-4

	-- params
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
		declare @today datetime = dbo.today()

		declare @mol_id int = (select mol_id from queues where queue_id = @queue_id)
		if @archive_date is not null set @queue_id = null
	-- #items
		create table #items(id int primary key)
		insert into #items exec mfr_provides_calc;90 @queue_id = @queue_id
	-- /*** DEBUG ***/
        -- DELETE FROM #ITEMS; INSERT INTO #ITEMS SELECT 5700
		-- SET @FILTER_ITEMS = 1
	-- #docs
		declare @calc_archive bit = case when @archive_date is not null then 1 end

		create table #docs(id int primary key)
		insert into #docs select distinct mfr_doc_id from mfr_r_provides
		where (@filter_items = 0 or item_id in (select id from #items))
        
	exec tracer_log @tid, 'insert rows with 100%'
		if @filter_items is null and exists(select 1 from mfr_r_provides where slice = '100%')
			delete from mfr_r_provides where slice = '100%'

		declare @real_archive_date date = 
			case 
				when not exists(select 1 from mfr_r_provides_archive)
					then '1900-01-01'
				else
					(select top 1 archive_date from mfr_r_provides_archive)	
			end

		insert into mfr_r_provides(
			acc_register_id,
			mfr_doc_id, item_id, unit_name, id_mfr, d_mfr, d_mfr_to, q_mfr, price, price_ship, slice
			)
		select 
			mfr.acc_register_id,
			c.mfr_doc_id, c.item_id, c.unit_name, c.content_id, c.opers_from, c.opers_to, c.q_brutto_product,
			c.item_price0, c.item_price0,
			'100%'
		from sdocs_mfr_contents c with(nolock)
			join mfr_sdocs mfr with(nolock) on mfr.doc_id = c.mfr_doc_id
		where c.is_buy = 1
			and c.cancel_reason_id in (1,2)
			and (
				(@archive_date is not null and mfr.d_issue < @archive_date)
				or (mfr.status_id >= 0 and isnull(mfr.d_issue, @real_archive_date) >= @real_archive_date)
				)
			and (@filter_items = 0 or c.item_id in (select id from #items))

	exec tracer_log @tid, '#provide_sums'
		-- #provide_sums
            update mfr_r_provides
            set status_id = 
                    case 
                        when slice = '100%' then 100 -- считаем выданным
                        when q_mfr < @PRECISION then 100 -- выдано (точность округления)
                        when q_job > 0 then 100 -- выдано
                        when q_lzk > 0 then 90 -- ЛЗК
                        when q_ship > 0 then 30 -- приход
                        when q_invoice > 0 then 25 -- счёт
                        when q_order > 0 then 20 -- заявка
                        else 0 -- черновик
                    end
            where (@filter_items = 0 or item_id in (select id from #items))

			create table #provide_sums(
				content_id int primary key clustered,
				item_id int index ix_item,
				unit_name varchar(20),
				content_unit_name varchar(20),
                status_id int,
				d_delivery date, d_provide date, d_ship date, d_job date,
				q_mfr float, q_invoice float, q_lzk float, q_job float, q_provided float
				)

			insert into #provide_sums(
				content_id, item_id, unit_name, content_unit_name,
                status_id,
                d_delivery, d_ship, d_job,
                q_mfr, q_invoice, q_lzk, q_job, q_provided
				)
			select 
				id_mfr,
				min(r.item_id),
				min(r.unit_name),
				min(c.unit_name),
				min(r.status_id),
				max(d_delivery),
				max(d_ship),
				max(d_job),
				isnull(sum(q_mfr), 0),
				isnull(sum(q_invoice), 0),
				isnull(sum(q_lzk), 0),
				isnull(sum(q_job), 0),
                sum(
                    isnull(case when q_ship > 0 and q_job is null then q_ship end, 0)
                    + isnull(q_lzk,0)
                    + isnull(q_job,0)
                )
            from mfr_r_provides r with(nolock)
				join sdocs_mfr_contents c with(nolock) on c.content_id = r.id_mfr
			where q_mfr > 0
				and (@filter_items = 0 or r.item_id in (select id from #items))
			group by id_mfr

		-- units
			declare @koef float

			update x set 
				@koef = coalesce(uk.koef, dbo.product_ukoef(x.unit_name, x.content_unit_name), 1),
				unit_name = x.content_unit_name,
				q_mfr = x.q_mfr * @koef,
				q_lzk = x.q_lzk * @koef,
				q_job = x.q_job * @koef,
				q_provided = x.q_provided * @koef
			from #provide_sums x					
				left join products_ukoefs uk on uk.product_id = x.item_id and uk.unit_from = x.unit_name and uk.unit_to = x.content_unit_name
			where x.unit_name != x.content_unit_name

		-- d_provide
			update #provide_sums set d_provide = d_ship where q_provided / nullif(q_mfr,0) >= 0.999

	EXEC SYS_SET_TRIGGERS 0
		exec tracer_log @tid, 'calc progress'

			-- #invoices_sums
            create table #invoices_sums(content_id int primary key, d_delivery date, days1 float, days2 float)

            insert into #invoices_sums(content_id, d_delivery, days1, days2)
            select 
                c.content_id,
                x.d_delivery,
                days1 = (select count(*) from calendar with(nolock) where 
                    [type] = case when isnull(pl.calendar_id, 1) = 1 then 0 else [type] end
                    and day_date between @today and x.d_delivery),
                days2 = (select count(*) from calendar with(nolock) where 
                    [type] = case when isnull(pl.calendar_id, 1) = 1 then 0 else [type] end
                    and day_date between c.opers_from_plan and c.opers_to_plan)
            from #provide_sums x
                join sdocs_mfr_contents c with(nolock) on c.content_id = x.content_id
                    left join mfr_plans pl on pl.plan_id = c.plan_id
            where c.is_buy = 1
                and x.d_delivery is not null
                and x.q_invoice > 0
                and isnull(c.is_manual_progress, 0) = 0
                and (@filter_items = 0 or c.item_id in (select id from #items))

			-- update progress
			update x
			set progress =
                    case
                        when @today >= inv.d_delivery then 0.99
                        when inv.days1 >= inv.days2 then 0.00
                        else 1 - inv.days1 / nullif(inv.days2, 0)
                    end
			from sdocs_mfr_opers x with(nolock)
				join #invoices_sums inv on inv.content_id = x.content_id

			exec drop_temp_table '#invoices_sums'

		exec tracer_log @tid, 'update statuses'

			update x
			set	status_id = xx.status_id,
				d_to_fact = case when xx.status_id = 100 then isnull(xx.d_provide, x.d_to_fact) end,
				fact_q = case when xx.status_id = 100 then xx.q_provided end
			from sdocs_mfr_opers x with(nolock)
				join #provide_sums xx on xx.content_id = x.content_id
                join sdocs_mfr_contents c with(nolock) on c.content_id = x.content_id
            where c.is_buy = 1
			
			update x
			set status_id = isnull(o.status_id,0),
				opers_to_fact = case when o.status_id = 100 then o.d_to_fact end,
				opers_fact_q = o.fact_q
			from sdocs_mfr_contents x with(nolock)
				join (
					select
						x.content_id,
						status_id = min(x.status_id),
						d_to_fact = max(d_to_fact),
						fact_q = min(fact_q)
					from sdocs_mfr_opers x with(nolock)
						join #provide_sums i on i.content_id = x.content_id
					group by x.content_id
				) o on o.content_id = x.content_id
			where x.is_buy = 1

			-- cancel_reason_id
				-- отмена потребности
				update x set status_id = 100 
				from sdocs_mfr_contents x
					join #provide_sums prv on prv.content_id = x.content_id
				where cancel_reason_id in (1,2)
					and x.status_id != 100

		exec tracer_log @tid, 'update q_provided'
			update c set 
				q_provided = r.q_lzk + r.q_job,
				q_provided_max = r.q_provided
			from sdocs_mfr_contents c with(nolock)
				join #docs i on i.id = c.mfr_doc_id
				join #provide_sums r on r.content_id = c.content_id

        exec drop_temp_table '#provide_sums'

		exec tracer_log @tid, 'update milestones (k_provided)'
            declare @exclude_types app_pkids
                insert @exclude_types select id from dbo.mfr_provides_excl_items(1)
                
                create table #items_types(type_id int primary key)
                    insert into #items_types 
                    select id from (
                        select distinct id = isnull(item_type_id,0) from sdocs_mfr_contents -- TODO ignatov
                        ) x
                    where not exists(select 1 from @exclude_types) or id not in (select id from @exclude_types)

            update x set k_provided = 1.00 * sum_provided / nullif(sum_materials,0)
			from sdocs_mfr_milestones x
				join (
					select
						o.mfr_doc_id, o.milestone_id,
						sum_materials = sum(cm.q_brutto_product * cm.item_price0),
						sum_provided = sum(cm.q_provided_max * cm.item_price0)
					from sdocs_mfr_opers o with(nolock)
						join #docs i on i.id = o.mfr_doc_id
						join mfr_milestones ms with(nolock) on ms.milestone_id = o.milestone_id
						join sdocs_mfr_contents c with(nolock) on c.content_id = o.content_id
						join sdocs_mfr_contents cm with(nolock) on cm.mfr_doc_id = c.mfr_doc_id and cm.product_id = c.product_id
							and cm.node.IsDescendantOf(c.node) = 1
							and cm.is_buy = 1
                        join #items_types itp on itp.type_id = isnull(cm.item_type_id,0)
					group by o.mfr_doc_id, o.milestone_id
				) xx on xx.mfr_doc_id = x.doc_id and xx.milestone_id = x.attr_id

            exec drop_temp_table '#items_types'
	EXEC SYS_SET_TRIGGERS 1

    -- patch: clear unnecessary reference
    update mfr_r_provides set d_invoice = null, id_invoice = null where q_invoice is null and id_invoice is not null

    exec tracer_log @tid, 'xslice'
		update x
		set xslice =
			case
				when slice = '100%' then 'manual'
				when q_mfr < @PRECISION then 'misc'
				when q_job > 0 then
					case
						when q_mfr > 0 and q_distrib > 0 then 'distrib'
						when q_mfr > 0 then 'job'
						else 'misc'
					end
				when q_mfr > 0 then
					case 
						when isnull(q_lzk,0) > 0 then 'lzk'
						when isnull(q_ship,0) = 0 and isnull(q_job,0) = 0 then 'deficit'
						when isnull(q_ship,0) > 0 and isnull(q_job,0) = 0 then 'ship'
						else 'misc'
					end
				when q_ship > 0 and isnull(q_job,0) = 0 then
					case when sd.type_id = 9 then 'stock' else 'misc' end
				when isnull(q_mfr,0) = 0 then 'zero'
				else 'misc'
			end
		from mfr_r_provides x
			left join sdocs sd on sd.doc_id = x.id_ship
		where xslice is null

        update x set xslice = 'coop'
        from mfr_r_provides x
            join sdocs_mfr_contents c on c.content_id = x.id_mfr and c.is_buy = 0

	exec tracer_log @tid, 'archive'
		if @calc_archive = 1 
		begin
			IF OBJECT_ID('MFR_R_PROVIDES_ARCHIVE') IS NOT NULL DROP TABLE MFR_R_PROVIDES_ARCHIVE
			SELECT *, 
				ARCHIVE = CAST(1 AS BIT),
				ARCHIVE_DATE = @ARCHIVE_DATE,
				ARCHIVE_USER = @MOL_ID
			INTO MFR_R_PROVIDES_ARCHIVE
			FROM MFR_R_PROVIDES
			
            update mfr_r_provides_archive set archive = 0
            where (q_invoice > 0 or q_ship > 0 or q_job > 0 or q_distrib > 0)
                and isnull(q_mfr,0) = 0

            update mfr_r_provides_archive set archive = 1
            where q_job > 0 and mfr_doc_id = 0

			create table #docs_archived(id int primary key)
				insert #docs_archived select doc_id from mfr_sdocs where d_issue < @archive_date and status_id >= 0

            update x set archive = 1
            from mfr_r_provides_archive x
                join #docs_archived a on a.id = x.mfr_doc_id

            update x set archive = 0
            from mfr_r_provides_archive x
            where archive = 1
                -- есть потребность
                and isnull(q_mfr,0) > 0
                -- и есть адресной выдача в будущем
                and exists(
                    select 1
                    from sdocs_products sp
                        join sdocs sd on sd.doc_id = sp.doc_id
                        join mfr_sdocs mfr on mfr.number = sp.mfr_number
                    where sd.type_id = 12
                        and sd.status_id >= 0
                        and x.mfr_doc_id = mfr.doc_id
                        and x.item_id = sp.product_id
                        and sd.d_doc >= @archive_date
                    )

            update mfr_r_provides_archive set archive = 0
            where (q_ship > 0 and isnull(q_job,0) = 0)

            update mfr_r_provides_archive set archive = 0
            where (q_job > 0 and isnull(q_ship,0) = 0)

            update mfr_r_provides_archive set archive = 1
            where archive = 0 and xslice = 'manual'
		end

	final:
		exec tracer_log @tid, 'finalize'
		exec drop_temp_table '#docs,#docs_archived,#items'
		if @trace = 1 exec tracer_view @tid
end
go

-- exec mfr_provides_calc;2 @debug_item_id = 129297
-- exec mfr_provides_calc;2 @debug = 1 --, @archive_date = '2024-06-01'
-- exec mfr_provides_calc;2
-- exec mfr_provides_calc;100 null, @trace = 1
