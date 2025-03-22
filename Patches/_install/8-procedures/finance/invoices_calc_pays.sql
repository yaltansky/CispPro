if object_id('invoices_calc_pays') is not null drop proc invoices_calc_pays
go
-- exec invoices_calc_pays 1000, @trace = 1
create proc invoices_calc_pays
	@mol_id int = null,
	@queue_id uniqueidentifier = null
as
begin
    declare @today date = dbo.today();
    declare @subject_id int = (select top 1 subject_id from mfr_plans where status_id between 0 and 99);
    declare @proc_name varchar(50) = object_name(@@procid);
    declare @tid_msg varchar(max) = concat(@proc_name, '.params:');
    declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out

		exec tracer_log @tid, @tid_msg

	if @queue_id is not null goto calc_fifo
	-- @ids
		declare @ids as app_pkids
			insert into @ids select doc_id from supply_invoices x
			where not exists(select 1 from sdocs_milestones where doc_id = x.doc_id)
				and isnull(x.source_id,0) != 1 -- кроме источника "КИСП"
	-- sdocs_milestones
		exec invoices_calc_milestones

		declare @ms_ready int = 2 -- Уведомление о готовности
		declare @ms_ship int = 3 -- Поступление на склад
		declare @ms_job int = 4 -- ЛЗК

		-- update "Дата уведомления о готовности"
			update x set d_to_fact = i.d_ready, progress = 1
			from sdocs_milestones x
				join supply_invoices i on i.doc_id = x.doc_id
			where i.d_ready is not null
				and x.milestone_id = @ms_ready

			create table #provides(
				doc_id int primary key,
				d_mfr date,
				d_ship date,
				d_job date,
				q_invoice decimal(18,3),
				q_ship decimal(18,3),
				q_job decimal(18,3)
				)
				insert into #provides(doc_id, d_mfr, d_ship, d_job, q_invoice, q_ship, q_job)
				select id_invoice, max(d_mfr), max(d_ship), max(d_job), sum(q_invoice), sum(q_ship), sum(q_job)
				from mfr_r_provides
				where id_invoice is not null
				group by id_invoice

		-- update "Поступило на склад"
			-- fact
			update x set d_to_fact = isnull(i.d_ship, i.d_ship), progress = 1
			from sdocs_milestones x
				join #provides i on i.doc_id = x.doc_id
			where x.milestone_id = @ms_ship
				and (i.q_invoice <= i.q_ship or i.q_invoice <= i.q_job)

		-- update "Выдано в производство"
			-- fact
			update x set d_to_fact = i.d_job, progress = 1
			from sdocs_milestones x
				join #provides i on i.doc_id = x.doc_id
			where x.milestone_id = @ms_job
				and i.q_invoice <= i.q_job
	-- FIFO (счета, оплаты, финансирование)
	    calc_fifo:
	    exec invoices_calc_pays;2 @queue_id = @queue_id, @tid = @tid
	-- final
        exec drop_temp_table '#provides'
        exec tracer_close @tid
end
GO
create proc invoices_calc_pays;2
	@queue_id uniqueidentifier = null,
	@tid int = 1
as
begin
	set nocount on;

	-- prepare
		declare @today date = dbo.today()

		create table #icp_docs(id int primary key)
		insert into #icp_docs select doc_id from mfr_sdocs where status_id >= 0
			or number = '160000-000' -- TODO: то ещё обобщение :(( Это некий обобщённый заказ, который используется в счетах
		
		-- #require
		select top 0 *,
		 	value = cast(null as float)
		into #require from supply_r_invpays
			create unique clustered index pk_require on #require(row_id)
			create index ix_require on #require(mfr_doc_id,item_id)

		-- #provide
		select top 0 *,
		 	value = cast(null as float)
		into #provide from supply_r_invpays
			create unique clustered index pk_provide on #provide(row_id)
			create index ix_provide on #provide(mfr_doc_id,item_id)

		-- #result
		select top 0 *,
			cast(null as int) as rq_row_id,
			cast(null as int) as pv_row_id
		into #result from supply_r_invpays
			create index ix_result on #result(mfr_doc_id,item_id)
			create index ix_result2 on #result(rq_row_id)
			create index ix_result3 on #result(pv_row_id)

		-- @queue_id
			declare @filter_docs bit = case when @queue_id is not null then 1 end
			
			if @queue_id is not null
			begin
				delete from #icp_docs
				
				if exists(select 1 from queues_objs where queue_id = @queue_id and obj_type = 'inv')
					-- счета
					insert into #icp_docs select distinct mfr.doc_id
					from supply_invoices_products x
						join mfr_sdocs mfr on mfr.number = x.mfr_number
					where x.doc_id in (select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'inv')

				else if exists(select 1 from queues_objs where queue_id = @queue_id and obj_type = 'invpay')
					-- строки журнала "Счета и оплаты"
					insert into #icp_docs select distinct mfr_doc_id
					from supply_r_invpays_totals
					where row_id in (select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'invpay')
			end

    exec tracer_log @tid, 'Счета поставщиков'
		create table #provides_items(
			doc_id int,
			mfr_doc_id int,
			item_id int,
			d_mfr date,
			d_mfr_to date,
			d_ship date,
			d_job date,
			q_mfr float,
			q_invoice float,
			q_ship float,
			q_job float,
			primary key clustered (doc_id, mfr_doc_id ,item_id)
			)
			insert into #provides_items(
				doc_id, mfr_doc_id, item_id, d_mfr, d_mfr_to, d_ship, d_job, q_mfr, q_invoice, q_ship, q_job
				)
			select 
				id_invoice, mfr_doc_id, item_id, 
				d_mfr = min(d_mfr), 
				d_mfr_to = min(d_mfr_to),
				d_ship = max(d_ship),
				d_job = max(d_job),
				q_mfr = sum(q_mfr), 
				q_invoice = sum(q_invoice),
				q_ship = sum(q_ship),
				q_job = sum(q_job)
			from (
                select 
                    mfr_doc_id, item_id,
                    id_mfr, id_invoice,
                    d_mfr, d_mfr_to, d_ship, d_job,
                    q_mfr, q_invoice, q_ship, q_job
                from mfr_r_provides
                where id_invoice is not null
                    and (mfr_doc_id = 0 or mfr_doc_id in (select id from #icp_docs))

                union all 

                select 
                    mfr_doc_id, item_id,
                    id_mfr, id_invoice,
                    d_mfr, d_mfr_to, d_ship, d_job,
                    q_mfr, q_invoice, q_ship, q_job
                from mfr_r_provides_archive
                where archive = 1
                    and id_invoice is not null
                    and (mfr_doc_id = 0 or mfr_doc_id in (select id from #icp_docs))
                ) r
			group by id_invoice, mfr_doc_id, item_id
        
        insert into #result(
            mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
            inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship,
            inv_value
            )
        select
            mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
            inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, 
            inv_ms_value
        from (
            select 
                mfr_doc_id = isnull(mfr.doc_id, 0),
                items.item_id,
                inv_d_plan = case
                    when ms.milestone_id = 1 then items.d_mfr
                    else items.d_mfr_to
                end,
                inv_d_condition = case
                    when ms.milestone_id = 1 then inv.d_doc
                    when ms.milestone_id in (2,3) 
                        and items.q_mfr <= isnull(items.q_ship,0) or items.q_mfr <= isnull(items.q_job,0)
                            then isnull(items.d_ship, items.d_job)
                end,
                inv_id = inv.doc_id,
                inv_date = inv.d_doc,
                inv_d_mfr = items.d_mfr,
                inv_d_mfr_to = items.d_mfr_to,
                inv_milestone_id = ms.milestone_id,
                inv_ms_d_plan = dateadd(d, isnull(ms.date_lag,0), ms.d_to),
                inv_ms_d_fact = ms.d_to_fact,
                inv_ms_value = ms.ratio * sp.value_rur * (items.q_invoice / totals.q),
                inv_q = items.q_invoice,
                inv_q_ship = items.q_ship
            from #provides_items items
                join (
                    select 
                        r.doc_id, r.item_id,
                        q = nullif(sum(ratio * q_invoice), 0)
                    from #provides_items r
                        join supply_invoices_milestones ms on ms.doc_id = r.doc_id
                    group by r.doc_id, r.item_id
                ) totals on totals.doc_id = items.doc_id and totals.item_id = items.item_id
                join supply_invoices inv on inv.doc_id = items.doc_id
                    join supply_invoices_milestones ms on ms.doc_id = inv.doc_id
                join (
                    select doc_id, product_id, value_rur = sum(value_rur)
                    from sdocs_products
                    group by doc_id, product_id
                ) sp on sp.doc_id = items.doc_id and sp.product_id = items.item_id
                left join mfr_sdocs mfr on mfr.doc_id = items.mfr_doc_id
            where ms.ratio * sp.value_rur > 0
            ) r
        order by r.inv_ms_d_plan, r.inv_d_plan

    exec tracer_log @tid, '+ Финансирование'
		declare @fid uniqueidentifier set @fid = newid()

		select top 0 *, cast(null as float) as value into #invoices from #result
			;create unique clustered index pk_require on #invoices(row_id)
			;create index ix_require on #invoices(mfr_doc_id,item_id)

		create table #funding(
			row_id int identity primary key,
			mfr_doc_id int index ix_mfr_doc,
			value float
			)

		exec tracer_log @tid, '    #invoices'
			insert into #invoices(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship,
				value
				)
			select
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship,
				inv_value
			from #result
			where inv_value > 0
			order by mfr_doc_id, inv_d_plan

			select * into #pays_unbound from #result where inv_value is null
			truncate table #result

		exec tracer_log @tid, '    #funding (финансирование)'
			insert into #funding(mfr_doc_id, value)
			select mfr.doc_id, -sum(isnull(x.value_fact,0) + isnull(x.value_fund,0))
			from deals_r_work_capital x
				join sdocs_mfr mfr on mfr.number = x.mfr_number
					join #icp_docs d on d.id = mfr.doc_id
			where x.article_group_name like '%материалы%'
			group by mfr.doc_id		
			having -sum(isnull(x.value_fact,0) + isnull(x.value_fund,0)) > 0
			order by mfr.doc_id

		exec tracer_log @tid, '    FIFO'
			exec fifo_clear @fid

			insert into #result(
				rq_row_id, pv_row_id,
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship,
				inv_value, inv_fund_value
				)
			select 
				r.row_id, p.row_id,
				r.mfr_doc_id, r.item_id, r.inv_d_plan, r.inv_d_condition,
				r.inv_id, r.inv_milestone_id, r.inv_date, r.inv_ms_d_plan, r.inv_ms_d_fact, r.inv_d_mfr, r.inv_d_mfr_to, r.inv_q, r.inv_q_ship,
				f.value, f.value
			from #invoices r
				join #funding p on p.mfr_doc_id = r.mfr_doc_id
				cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
			order by r.row_id, p.row_id

		exec tracer_log @tid, '    reminds'
			insert into #result(
				rq_row_id, pv_row_id,
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value,
				inv_fund_value
				)
			select 
				r.row_id, p.row_id,
				isnull(r.mfr_doc_id, p.mfr_doc_id), isnull(r.item_id,0),
				r.inv_d_plan, r.inv_d_condition,
				-- require
				r.inv_id, r.inv_milestone_id, r.inv_date, r.inv_ms_d_plan, r.inv_ms_d_fact, r.inv_d_mfr, r.inv_d_mfr_to, r.inv_q, r.inv_q_ship, f.rq_value,
				-- provide
				f.pv_value
			from dbo.fifo_reminds(@fid) f
				left join #invoices r on r.row_id = f.rq_row_id
				left join #funding p on p.row_id = f.pv_row_id

		exec tracer_log @tid, '    left (not in)'
			insert into #result(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship,
				inv_value
				)
			select 
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship,
				value
			from #invoices r
			where not exists(select 1 from #result where rq_row_id = r.row_id)
		
		exec tracer_log @tid, '    right (not in)'
			insert into #result(mfr_doc_id, item_id, inv_fund_value)
			select mfr_doc_id, 0, value
			from #funding x
			where not exists(select 1 from #result where pv_row_id = x.row_id)

		exec fifo_clear @fid
	
    exec tracer_log @tid, '+ Оплаты'
		truncate table #invoices

        -- table
            create table #inv_findocs(
                row_id int identity primary key,
                invoice_id int,
                findoc_id int,
                value float
                )

        -- #inv_findocs
            insert into #inv_findocs(invoice_id, findoc_id, value)
            select x.invoice_id, x.findoc_id, -x.value_rur
            from findocs_invoices x
                join findocs f on f.findoc_id = x.findoc_id
                left join supply_invoices i on i.doc_id = x.invoice_id
            where x.invoice_id in (select distinct invoice_id from #result where invoice_id is not null)
                and -x.value_rur > 0
            order by f.d_doc, x.findoc_id, i.d_doc, x.invoice_id

		-- #invoices
			insert into #invoices(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
				value
				)
			select
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
				inv_value
			from #result
			where inv_value > 0
			order by inv_d_plan, mfr_doc_id, item_id

			exec drop_temp_table '#invoices_unbound'
			select * into #invoices_unbound from #result where isnull(inv_value,0) = 0
			truncate table #result

		exec tracer_log @tid, '    FIFO'
			exec fifo_clear @fid

			insert into #result(
				rq_row_id, pv_row_id,
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
				findoc_id, findoc_value
				)
			select 
				r.row_id, p.row_id,
				r.mfr_doc_id, r.item_id, r.inv_d_plan, r.inv_d_condition,
				-- invoice
				r.inv_id, r.inv_milestone_id, r.inv_date, r.inv_ms_d_plan, r.inv_ms_d_fact, r.inv_d_mfr, r.inv_d_mfr_to, r.inv_q, r.inv_q_ship,
				f.value,
				case when r.inv_fund_value is not null then f.value end,
				-- findoc
				p.findoc_id,
				f.value
			from #invoices r
				join #inv_findocs p on p.invoice_id = r.inv_id
				cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
			order by r.row_id, p.row_id

		exec tracer_log @tid, '    reminds'
			insert into #result(
				rq_row_id, pv_row_id,
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
				findoc_id, findoc_value
				)
			select 
				r.row_id, p.row_id,
				isnull(r.mfr_doc_id, 0), isnull(r.item_id,0),
				r.inv_d_plan, r.inv_d_condition,
				-- invoice
				isnull(r.inv_id, p.invoice_id), r.inv_milestone_id, r.inv_date, r.inv_ms_d_plan, r.inv_ms_d_fact, r.inv_d_mfr, r.inv_d_mfr_to, r.inv_q, r.inv_q_ship,
				f.rq_value,
				case when r.inv_fund_value is not null then f.rq_value end,
				-- findoc
				p.findoc_id, f.pv_value
			from dbo.fifo_reminds(@fid) f
				left join #invoices r on r.row_id = f.rq_row_id
				left join #inv_findocs p on p.row_id = f.pv_row_id

		exec tracer_log @tid, '    left (not in)'
			insert into #result(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value
				)
			select 
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				-- invoice
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, value, inv_fund_value
			from #invoices r
			where not exists(select 1 from #result where rq_row_id = r.row_id)
		
		exec tracer_log @tid, '    right (not in)'
			insert into #result(inv_id, mfr_doc_id, item_id, findoc_id, findoc_value)
			select invoice_id, 0, 0, findoc_id, value
			from #inv_findocs x
			where not exists(select 1 from #result where pv_row_id = x.row_id)

		exec tracer_log @tid, '    misc'
			insert into #result(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value
				)
			select
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value
			from #invoices_unbound

		exec fifo_clear @fid
	
    exec tracer_log @tid, '+ Заявки на оплату'
		truncate table #invoices

        -- table
            create table #inv_payorders(
                row_id int identity primary key,
                invoice_id int,
                payorder_id int,
                value float
                );
                create index ix_invoices on #inv_payorders(invoice_id);

        -- #inv_payorders
            insert into #inv_payorders(invoice_id, payorder_id, value)
            select x.invoice_id, x.payorder_id, sum(x.value_rur)
            from payorders_materials x
                join payorders f on f.payorder_id = x.payorder_id
                left join supply_invoices i on i.doc_id = x.invoice_id
            where x.invoice_id in (select distinct invoice_id from #result where invoice_id is not null)
            group by x.invoice_id, x.payorder_id
            having sum(x.value_rur) > 0
 
		-- #invoices
			insert into #invoices(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
                findoc_id, findoc_value,
				value
				)
			select
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
                findoc_id, findoc_value,
				inv_value
			from #result
			where inv_value > 0
			order by inv_d_plan, mfr_doc_id, item_id

			select * into #invoices_unbound2 from #result where isnull(inv_value,0) = 0
			truncate table #result

		exec tracer_log @tid, '    FIFO'
			exec fifo_clear @fid

			insert into #result(
				rq_row_id, pv_row_id,
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
				findoc_id, findoc_value,
				payorder_id, payorder_value
				)
			select 
				r.row_id, p.row_id,
				r.mfr_doc_id, r.item_id, r.inv_d_plan, r.inv_d_condition,
				-- invoice
				r.inv_id, r.inv_milestone_id, r.inv_date, r.inv_ms_d_plan, r.inv_ms_d_fact, r.inv_d_mfr, r.inv_d_mfr_to, r.inv_q, r.inv_q_ship,
                f.value,
                case when r.inv_fund_value is not null then f.value end,
				-- findoc
				r.findoc_id, 
				case when r.findoc_value is not null then f.value end,
				-- payorder
				p.payorder_id, f.value
			from #invoices r
				join #inv_payorders p on p.invoice_id = r.inv_id
				cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
			order by r.row_id, p.row_id

		exec tracer_log @tid, '    reminds'
			insert into #result(
				rq_row_id, pv_row_id,
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
				findoc_id, findoc_value,
				payorder_id, payorder_value
				)
			select 
				r.row_id, p.row_id,
				isnull(r.mfr_doc_id, 0), isnull(r.item_id,0),
				r.inv_d_plan, r.inv_d_condition,
				-- invoice
				isnull(r.inv_id, p.invoice_id), r.inv_milestone_id, r.inv_date, r.inv_ms_d_plan, r.inv_ms_d_fact, r.inv_d_mfr, r.inv_d_mfr_to, r.inv_q, r.inv_q_ship,
				f.rq_value,
				case when r.inv_fund_value is not null then f.rq_value end,
				-- findoc
				r.findoc_id,
				case when r.findoc_value is not null then f.rq_value end,
				-- payorder
				p.payorder_id, f.pv_value
			from dbo.fifo_reminds(@fid) f
				left join #invoices r on r.row_id = f.rq_row_id
				left join #inv_payorders p on p.row_id = f.pv_row_id

		exec tracer_log @tid, '    left (not in)'
			insert into #result(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value, findoc_id, findoc_value
				)
			select 
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				-- invoice
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, value, inv_fund_value,
				-- findoc
				findoc_id, findoc_value
			from #invoices r
			where not exists(select 1 from #result where rq_row_id = r.row_id)
		
		exec tracer_log @tid, '    right (not in)'
			insert into #result(inv_id, mfr_doc_id, item_id, payorder_id, payorder_value)
			select invoice_id, 0, 0, payorder_id, value
			from #inv_payorders x
			where not exists(select 1 from #result where pv_row_id = x.row_id)

		exec tracer_log @tid, '    misc'
			insert into #result(
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value, findoc_id, findoc_value
				)
			select
				mfr_doc_id, item_id, inv_d_plan, inv_d_condition,
				inv_id, inv_milestone_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value, findoc_id, findoc_value
			from #invoices_unbound2

            drop table #invoices_unbound2;

		exec fifo_clear @fid

    -- Контрольная сумма
		if @tid > 0
			select
				'контрольная сумма invoices_calc_pays'
				, check_inv = inv - isnull(r_inv,0)			
				, check_fund = fund - isnull(r_fund,0)
				, check_findoc = findoc - isnull(r_findoc,0)
				, check_payorder = payorder - isnull(r_payorder,0)
			from (
			select 
				cast((select sum(value) from #invoices) as decimal) as 'inv'
				, cast((select sum(inv_value) from #result) as decimal) as 'r_inv'
				, cast((select sum(value) from #funding) as decimal) as 'fund'
				, cast((select sum(inv_fund_value) from #result) as decimal) as 'r_fund'
				, cast((select sum(value) from #inv_findocs) as decimal) as 'findoc'
				, cast((select sum(findoc_value) from #result) as decimal) as 'r_findoc'
				, cast((select sum(value) from #inv_payorders) as decimal) as 'payorder'
				, cast((select sum(payorder_value) from #result) as decimal) as 'r_payorder'
				) u

    -- POST-обработка
		exec tracer_log @tid, 'save supply_r_invpays'
			if @filter_docs is null
				truncate table supply_r_invpays
			else
				delete x from supply_r_invpays x
					join #icp_docs d on d.id = x.mfr_doc_id

			insert into supply_r_invpays(
				acc_register_id, mfr_doc_id, item_id, 
                inv_d_plan, inv_d_condition, inv_milestone_id, inv_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value,
                findoc_id, findoc_value,
                payorder_id, payorder_value
				)
			select
				coalesce(mfr.acc_register_id, inv.acc_register_id, 0), r.mfr_doc_id, r.item_id,
                inv_d_plan, inv_d_condition, inv_milestone_id, inv_id, inv_date, inv_ms_d_plan, inv_ms_d_fact, inv_d_mfr, inv_d_mfr_to, inv_q, inv_q_ship, inv_value, inv_fund_value, 
                findoc_id, findoc_value,
                payorder_id, payorder_value
			from #result r
				left join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
				left join supply_invoices inv on inv.doc_id = r.inv_id

			exec tracer_log @tid, '    set inv_condition, inv_condition_pay, inv_condition_fund'
			update x set 
				plan_id = sd.plan_id,
				inv_condition = case when x.inv_d_condition is not null then 'выполнены' else 'не выполнены' end,
				inv_condition_pay =
					case
						when x.inv_value <= isnull(x.findoc_value,0) then 'оплачено'
						else 'не оплачено'
					end,			
				inv_condition_fund = case when x.inv_value > 0 and x.inv_fund_value > 0 then 'финансировано' else 'не финансировано' end
			from supply_r_invpays x
				join sdocs sd on sd.doc_id = x.mfr_doc_id
			where @filter_docs is null or x.mfr_doc_id in (select id from #icp_docs)

            update x set 
                inv_condition_pay = 'переплачено',
                inv_id = inv.doc_id,
                inv_date = inv.d_doc
            from supply_r_invpays x
                join supply_invoices inv on inv.doc_id = x.inv_id
            where inv_id > 0 and isnull(inv_value,0) = 0

		exec tracer_log @tid, 'update product_id'
            update x set product_id = xx.product_id
            from supply_r_invpays x
                join (
                    select mfr.doc_id, product_id = max(sp.product_id)
                    from sdocs_products sp
                        join mfr_sdocs mfr on mfr.doc_id = sp.doc_id
                    group by mfr.doc_id having count(*) = 1
                ) xx on x.mfr_doc_id = xx.doc_id

		exec tracer_log @tid, 'update invoices'
            update x set findoc_date = f.d_doc
            from supply_r_invpays x
                join findocs f on f.findoc_id = x.findoc_id
			
            update x set d_to_fact = r.paid_date, progress = 1
			from supply_invoices_milestones x
				join (
					select inv_id, inv_milestone_id, paid_date = max(findoc_date)
					from supply_r_invpays
					group by inv_id, inv_milestone_id
					having sum(inv_value) <= sum(findoc_value)
				) r on r.inv_id = x.doc_id and r.inv_milestone_id = x.milestone_id
			where (@filter_docs is null or x.doc_id in (select id from #icp_docs))
		
			exec sys_set_triggers 0
				update sdocs set status_id = 100
				where doc_id in (
					select inv_id from supply_r_invpays group by inv_id having sum(inv_value) <= sum(findoc_value)
					)
					and (@filter_docs is null or doc_id in (select id from #icp_docs))
			exec sys_set_triggers 1

		exec tracer_log @tid, 'save supply_r_invpays_totals'

			select top 0 * into #totals from supply_r_invpays_totals
				create index ix_totals on #totals (inv_id, inv_milestone_id, mfr_doc_id, item_id)
				alter table #totals add id int identity primary key

			insert into #totals(
				row_id,
				acc_register_id,
				inv_id, inv_milestone_id, mfr_doc_id, product_id, item_id,
				inv_condition, inv_condition_pay, inv_condition_fund,
				inv_date, inv_d_mfr, inv_d_mfr_to, inv_d_plan, inv_ms_d_plan, inv_q, inv_q_ship,
				inv_value, findoc_value, payorder_value, inv_fund_value
				)
			select
				0,
				acc_register_id,
				inv_id, inv_milestone_id, mfr_doc_id, product_id, item_id,
				min(inv_condition),
				min(inv_condition_pay),
				min(inv_condition_fund),
				min(inv_date),			
				min(inv_d_mfr),
				min(inv_d_mfr_to),
				min(inv_d_plan),
				min(inv_ms_d_plan),
				min(inv_q),
				min(inv_q_ship),
				sum(inv_value),
				sum(findoc_value),
				sum(payorder_value),
				sum(inv_fund_value)
			from 
				supply_r_invpays x
			where 
				inv_id is not null
				and (@filter_docs is null or x.mfr_doc_id in (select id from #icp_docs))
			group by
				acc_register_id, inv_id, inv_milestone_id, mfr_doc_id, product_id, item_id

			update x set row_id = xx.row_id
			from #totals x
				join supply_r_invpays_totals xx on 
					xx.inv_id = x.inv_id
					and xx.inv_milestone_id = x.inv_milestone_id
					and xx.mfr_doc_id = x.mfr_doc_id
					and xx.item_id = x.item_id

			declare @seed int = isnull((select max(row_id) from supply_r_invpays_totals), 0)

			update x set row_id = @seed + xx.row_id
			from #totals x
				join (
					select id, row_id = row_number() over (order by inv_id, inv_milestone_id, mfr_doc_id, item_id)
					from #totals
					where row_id = 0				
				) xx on xx.id = x.id

			if @filter_docs is null
				truncate table supply_r_invpays_totals
			else
				delete x from supply_r_invpays_totals x
					join #icp_docs d on d.id = x.mfr_doc_id

			insert into supply_r_invpays_totals(
				row_id,
				acc_register_id,
				inv_id, inv_milestone_id, mfr_doc_id, product_id, item_id,
				inv_condition, inv_condition_pay, inv_condition_fund,
				inv_date, inv_d_mfr, inv_d_mfr_to, inv_d_plan, inv_ms_d_plan, inv_q, inv_q_ship,
				inv_value, findoc_value, payorder_value, inv_fund_value
				)
			select
				row_id,
				acc_register_id,
				inv_id, inv_milestone_id, mfr_doc_id, product_id, item_id,
				inv_condition, inv_condition_pay, inv_condition_fund,
				inv_date, inv_d_mfr, inv_d_mfr_to, inv_d_plan, inv_ms_d_plan, inv_q, inv_q_ship,
				inv_value, findoc_value, payorder_value, inv_fund_value			
			from #totals

    final:
		if @fid is not null exec fifo_clear @fid
		exec drop_temp_table '#icp_docs,#provides_items,#require,#provide,#result,#invoices,#pays_unbound,#funding,#totals'
end
GO
