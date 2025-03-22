if object_id('mfr_docs_trf_matchdocs') is not null drop proc mfr_docs_trf_matchdocs
go
create proc mfr_docs_trf_matchdocs
	@mol_id int,
	@doc_id int,
	@queue_id uniqueidentifier = null
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET XACT_ABORT ON;

	-- params
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
		declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
		declare @filter_items as bit = case
				when exists(
					select 1 from sdocs_mfr_contents c
						join @buffer b on b.id = c.content_id and c.is_buy = 1
					) then 1
				else 0
			end
		-- выборка мат.потребности осуществляется в привязке к ПЛАНУ
		declare @plan_id int = (select plan_id from sdocs where doc_id = @doc_id)

	-- "остатки" материалов для подбора заказов (#stock)
		create table #details (
			detail_id int primary key,
			acc_register_id int,
            item_id int,
			unit_name varchar(20),
			quantity float
			)
		insert into #details(detail_id, acc_register_id, item_id, unit_name, quantity)
		select sp.detail_id, isnull(mfr.acc_register_id,0), sp.product_id, u.name, sp.quantity
		from sdocs_products sp
			left join mfr_sdocs mfr on mfr.number = sp.mfr_number
			join products_units u on u.unit_id = sp.unit_id
		where sp.doc_id = @doc_id
			and mfr.doc_id is null -- не привязанные к заказам строки

		if not exists(select 1 from #details)		
		begin
			raiserror('В документе нет остатков для подбора мат. потребности по заказам.', 16, 1)
			return
		end

		if exists(
			select 1 from #details group by item_id
			having count(distinct unit_name) > 1
			)		
		begin
			raiserror('Для одного материала в документе должна быть указана одна единица измерения.', 16, 1)
			return
		end

		create table #stock(
			row_id int identity primary key,
			acc_register_id int,
            item_id int,
			unit_name varchar(20),
			value float
			)
			create unique index ix_join on #stock(acc_register_id, item_id)

		insert into #stock(acc_register_id, item_id, unit_name, value)
		select acc_register_id, item_id, unit_name, sum(quantity)
		from #details 
		group by acc_register_id, item_id, unit_name 
        order by acc_register_id, item_id, unit_name

	-- мат. потребность в заказвх (#mfr)
		create table #contents(content_id int primary key, acc_register_id int, unit_name varchar(20), q_left float)

		insert into #contents(acc_register_id, content_id, unit_name, q_left)
		select isnull(acc_register_id,0), id_mfr, unit_name, q_mfr - (q_lzk + q_job)
		from (
			select 
				r.acc_register_id,
                id_mfr,
				r.unit_name,
				q_mfr = sum(q_mfr),
				q_lzk = isnull(sum(q_lzk), 0),
				q_job = isnull(sum(q_job), 0),
				q_ship = sum(q_ship)
			from mfr_r_provides r
				join sdocs_mfr_contents c on c.content_id = r.id_mfr
				join mfr_sdocs mfr on 
						mfr.plan_id = isnull(@plan_id, mfr.plan_id)
					and mfr.doc_id = r.mfr_doc_id 
					and mfr.plan_status_id = 1 and mfr.status_id between 0 and 99
				join (
					select distinct item_id from #stock
				) s on s.item_id = r.item_id				
			where (
				@filter_items = 0
				or r.id_mfr in (select id from @buffer)
				)
				and isnull(c.is_manual_progress,0) = 0
			group by r.acc_register_id, r.id_mfr, r.unit_name
			having sum(q_mfr) > 0
			) x
		where (q_mfr - (q_lzk + q_job)) >= 0.000001

		create table #mfr(
			row_id int identity primary key,
			acc_register_id int,
            item_id int,
			mfr_doc_id int,
			due_date date,
			unit_name varchar(20),
			value float,
            index ix_join (acc_register_id, item_id)
			)
		insert into #mfr(acc_register_id, item_id, mfr_doc_id, due_date, unit_name, value)
		select acc_register_id, item_id, mfr_doc_id, due_date, unit_name, q_left
		from (
			select r.acc_register_id, c.mfr_doc_id, mfr.priority_final, c.item_id, due_date = min(c.opers_from_plan),
				r.unit_name,
				q_left = sum(r.q_left)
			from #contents r
				join sdocs_mfr_contents c on c.content_id = r.content_id
					join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id
			group by r.acc_register_id, c.mfr_doc_id, mfr.priority_final, c.item_id, r.unit_name
			) x
		order by acc_register_id, item_id, priority_final, due_date

		if not exists(select 1 from #mfr)
		begin
			declare @filter_items_text varchar(max) = case when @filter_items = 1 then 'используется буфер потребности' else 'буфер потребности не используется' end
			raiserror('Не удалось идентифицировать мат. потребность (%s). Проверьте соответствие папки плана заказа и данного документа.', 16, 1, @filter_items_text)
			return
		end

	-- units
		create table #products(product_id int primary key, unit_name varchar(20))
			insert into #products(product_id, unit_name)
			select item_id, min(unit_name) from #stock group by item_id

		declare @koef float

		update x set 
			@koef = isnull(uk.koef, dbo.product_ukoef(x.unit_name, p.unit_name)),
			unit_name = case when @koef is not null then p.unit_name else x.unit_name end,
			value = x.value * isnull(@koef, 1)
		from #mfr x
			join #products p on p.product_id = x.item_id
			left join products_ukoefs uk on uk.product_id = x.item_id and uk.unit_from = x.unit_name and uk.unit_to = p.unit_name
		where x.unit_name != p.unit_name

	-- FIFO
		declare @result table(
			rq_row_id int index ix_rq_row,
			acc_register_id int , 
			item_id int , 
			mfr_doc_id int,
			due_date date,
			unit_name varchar(20),
			value float
			)
		
		declare @fid uniqueidentifier = newid()

		-- join 
		insert into @result(rq_row_id, acc_register_id, item_id, mfr_doc_id, due_date, unit_name, value)
		select r.row_id, r.acc_register_id, r.item_id, p.mfr_doc_id, p.due_date, p.unit_name, f.value
		from #stock r
			join #mfr p on p.acc_register_id = r.acc_register_id and p.item_id = r.item_id and p.unit_name = r.unit_name
			cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
		order by r.row_id, p.row_id

		-- left1
		insert into @result(rq_row_id, acc_register_id, item_id, unit_name, value)
		select x.row_id, x.acc_register_id, x.item_id, x.unit_name, f.value
		from dbo.fifo_left(@fid) f
			join #stock x on x.row_id = f.row_id
		where f.value > 0

		-- left2
		insert into @result(acc_register_id, item_id, unit_name, value)
		select acc_register_id,  item_id, unit_name, value
		from #stock x
		where not exists(select 1 from @result where rq_row_id = x.row_id)

		exec fifo_clear @fid

	-- save results
		select product_id = r.item_id, r.due_date, mfr_number = mfr.number, u.unit_id, quantity = sum(r.value)
		into #newdetails
		from @result r		
			left join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
			join products_units u on u.name = r.unit_name
		group by r.item_id, r.due_date, mfr.number, u.unit_id
		having sum(r.value) > 0.000001

		delete x from sdocs_products x
			join #details s on s.detail_id = x.detail_id

		insert into sdocs_products(doc_id, product_id, due_date, mfr_number, unit_id, plan_q, quantity)
		select @doc_id, product_id, due_date, mfr_number, unit_id, quantity, quantity
		from #newdetails

	-- recalc provides
		if exists(select 1 from #newdetails)
		begin
			declare @items as app_pkids; insert into @items select distinct product_id from #newdetails
			exec mfr_provides_calc @mol_id = @mol_id, @items = @items, @queue_id = @queue_id
		end

	final:
		exec drop_temp_table '#details,#stock,#contents,#mfr,#products,#newdetails'
end
go
