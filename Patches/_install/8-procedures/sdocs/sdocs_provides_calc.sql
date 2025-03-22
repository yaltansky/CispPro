if object_id('sdocs_provides_calc') is not null drop proc sdocs_provides_calc
go
-- exec sdocs_provides_calc 1000, @trace = 1
create proc sdocs_provides_calc
	@mol_id int = null,
	@trace bit = 0
as
begin
	
	set nocount on;

	begin
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @echo = @trace, @trace_id = @tid out

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @mol_id=', @mol_id
			)
		exec tracer_log @tid, @tid_msg

		-- #require
			select top 0 *, cast(null as decimal(18,2)) as value into #require from sdocs_provides
				create unique clustered index pk_require on #require(row_id)
				create index ix_require on #require(stock_id,product_id)

		-- #provide
			select top 0 *, cast(null as decimal(18,2)) as value into #provide from sdocs_provides
				create unique clustered index pk_provide on #provide(row_id)
				create index ix_provide on #provide(stock_id,product_id)

		-- #result
			select top 0 * into #result from sdocs_provides
			create index ix_result on #result(stock_id,product_id)
	end -- prepare
	
	declare @products app_pkids; -- insert into @products values (112537)
	declare @filter_products bit = case when exists(select 1 from @products) then 1 end

	begin
		exec tracer_log @tid, 'MIX1 = FIFO(Запуски, Выпуски)'

		insert into #require(stock_id, product_id, id_mfr, d_mfr, d_issue_plan, value)
		select stock_id, product_id, doc_id, d_doc, d_issue, quantity
		from v_sdocs_products
		where type_id = 2
			and (@filter_products is null or product_id in (select id from @products))
		order by stock_id, product_id, d_doc, doc_id

		insert into #provide(stock_id, product_id, id_issue, d_issue, value)
		select stock_id, product_id, doc_id, d_doc, quantity
		from v_sdocs_products
		where type_id = 3
			and (@filter_products is null or product_id in (select id from @products))
		order by stock_id, product_id, d_doc, doc_id

		-- FIFO
			declare @fid uniqueidentifier set @fid = newid()

			insert into #result(
				stock_id, product_id,
				id_mfr, id_issue, d_mfr, d_issue_plan, d_issue,
				q_mfr, q_issue, slice, note
				)
			select 
				p.stock_id, p.product_id,
				r.id_mfr, p.id_issue, r.d_mfr, r.d_issue_plan, p.d_issue,
				f.value, f.value,
				'MIX1', 'FIFO(Запуски, Выпуски)'
			from #require r
				join #provide p on p.stock_id = r.stock_id and p.product_id = r.product_id and r.d_mfr <= p.d_issue
				cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
			order by r.row_id, p.row_id

		-- left (запуски без выпусков)
			insert into #result(stock_id, product_id, id_mfr, d_mfr, d_issue_plan, q_mfr, slice, note)
			select 
				x.stock_id, x.product_id,
				x.id_mfr, x.d_mfr, x.d_issue_plan, f.value,
				'MIX1.left', 'запуски без выпусков'
			from dbo.fifo_left(@fid) f
				join #require x on x.row_id = f.row_id
			where f.value > 0

		-- !link: stock_id, product_id
			insert into #result(stock_id, product_id, id_mfr, d_mfr, d_issue_plan, q_mfr, slice, note)
			select 
				x.stock_id, x.product_id,
				x.id_mfr, x.d_mfr, x.d_issue_plan, x.value,
				'MIX1.left', 'запуски без выпусков (!products)'
			from #require x
			where not exists(select 1 from #provide where stock_id = x.stock_id and product_id = x.product_id)
			
		-- !link: по дате
			insert into #result(stock_id, product_id, id_mfr, d_mfr, d_issue_plan, q_mfr, slice, note)
			select 
				x.stock_id, x.product_id,
				x.id_mfr, x.d_mfr, x.d_issue_plan, x.value,
				'MIX1.left', 'запуски без выпусков (по дате)'
			from #require x
			where not exists(select 1 from #result where id_mfr = x.id_mfr and product_id = x.product_id)
		
		-- right (выпуски без запусков)
			insert into #result(stock_id, product_id, id_issue, d_issue, q_issue, slice, note)
			select 
				x.stock_id, x.product_id,
				x.id_issue, x.d_issue, f.value,
				'MIX1.right', 'выпуски без запусков'
			from dbo.fifo_right(@fid) f
				join #provide x on x.row_id = f.row_id
			where f.value > 0
		
		-- !link: stock_id, product_id
			insert into #result(stock_id, product_id, id_issue, d_issue, q_issue, slice, note)
			select 
				x.stock_id, x.product_id,
				x.id_issue, x.d_issue, x.value,
				'MIX1.right', 'выпуски без запусков (!products)'
			from #provide x
			where not exists(select 1 from #require where stock_id = x.stock_id and product_id = x.product_id)

		-- !link: по дате
			insert into #result(stock_id, product_id, id_issue, d_issue, q_issue, slice, note)
			select 
				x.stock_id, x.product_id,
				x.id_issue, x.d_issue, x.value,
				'MIX1.right', 'выпуски без запусков (по дате)'
			from #provide x
			where not exists(select 1 from #result where id_issue = x.id_issue and product_id = x.product_id)

			insert into #result(stock_id, product_id, id_issue, d_issue, q_issue, slice, note)
			select stock_id, product_id, doc_id, d_doc, quantity, 'MIX1.right', 'Перемещения (приход)'
			from v_sdocs_products				
			where type_id = 7 and quantity > 0
				and (@filter_products is null or product_id in (select id from @products))

		-- /***/ SELECT 'STEP1', SUM(Q_MFR) 'Q_MFR', SUM(Q_ISSUE) 'Q_ISSUE', SUM(Q_SHIP) 'Q_SHIP', SUM(Q_ORDER) 'Q_SHIP' FROM #RESULT
	end -- MIX1 = FIFO(Запуски, Выпуски) + Перемещения(приход)

	begin
		exec tracer_log @tid, 'MIX2 = FIFO(MIX1, Отгрузки + Перещения (расход))'
		
		delete from #require
		delete from #provide
		update #result set slice = 'mix1' where id_issue is not null

		insert into #require(
			stock_id, product_id, d_mfr, d_issue_plan, d_issue, id_mfr, id_issue, q_mfr, q_issue, value		
			)
		select 
			stock_id, product_id, d_mfr, d_issue_plan, d_issue, id_mfr, id_issue, q_mfr, q_issue, q_issue		
		from #result
		where slice = 'mix1'
		order by product_id, d_issue

		insert into #provide(stock_id, product_id, agent_id, d_ship, id_ship, value)
		select stock_id, product_id, agent_id, d_ship, id_ship, quantity
		from (
			-- отгрузки
			select stock_id, product_id, agent_id, d_doc as d_ship, doc_id as id_ship, quantity,
				cast(0 as bit) as is_move
			from v_sdocs_products			
			where type_id = 4				
			
			-- перемещения (расход)
			UNION ALL
			select stock_id, product_id, null, d_doc, doc_id, -quantity,
				1 -- is_move
			from v_sdocs_products
			where type_id = 7 and quantity < 0
			) u		
		where (@filter_products is null or product_id in (select id from @products))
		order by stock_id, product_id, d_ship, id_ship

		-- FIFO
			exec fifo_clear @fid;
			insert into #result(
				stock_id, product_id, agent_id,
				id_mfr, id_issue, id_ship,
				d_mfr, d_issue_plan, d_issue, d_ship,
				q_mfr, q_issue, q_ship,
				slice, note
				)
			select 
				p.stock_id, p.product_id, p.agent_id,
				r.id_mfr, r.id_issue, p.id_ship,
				r.d_mfr, r.d_issue_plan, r.d_issue, p.d_ship,
				--
				case when r.q_mfr is not null then f.value end,
				f.value, f.value,
				--
				'MIX2', 'FIFO(MIX1, Отгрузки)'
			from #require r
				join #provide p on p.stock_id = r.stock_id and p.product_id = r.product_id
				cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
			order by r.row_id, p.row_id

		-- left (выпуски без отгрузки)
			insert into #result(
				stock_id, product_id, 
				id_mfr, id_issue, d_mfr, d_issue_plan, d_issue,
				q_mfr, q_issue, slice, note
				)		
			select
				x.stock_id, x.product_id,
				x.id_mfr, x.id_issue, x.d_mfr, x.d_issue_plan, x.d_issue,
				--
				case when x.q_mfr is not null then f.value end,
				f.value,
				--
				'MIX2.left', 'выпуски без отгрузки'
			from dbo.fifo_left(@fid) f
				join #require x on x.row_id = f.row_id
			where f.value > 0

		-- !link
			insert into #result(
				stock_id, product_id,
				id_mfr, id_issue, d_mfr, d_issue_plan, d_issue, q_mfr, q_issue,  slice, note
				)
			select 
				x.stock_id, x.product_id,
				x.id_mfr, x.id_issue,
				x.d_mfr, x.d_issue_plan, x.d_issue,
				x.q_mfr, x.q_issue,
				'MIX2.left', 'выпуски без отгрузки (!products)'
			from #require x
			where not exists(select 1 from #provide where stock_id = x.stock_id and product_id = x.product_id)

		-- right (отгрузки без выпусков)
			insert into #result(
				stock_id, product_id, agent_id,
				id_ship,
				d_ship, q_ship,
				slice, note
				)
			select 
				x.stock_id, x.product_id, x.agent_id,
				x.id_ship,
				x.d_ship, case when x.id_ship is not null then f.value end,
				'MIX2.right', 'отгрузки без выпусков'
			from dbo.fifo_right(@fid) f
				join #provide x on x.row_id = f.row_id
			where f.value > 0

		-- !link
			insert into #result(
				stock_id, product_id, agent_id,
				id_ship,
				d_ship, q_ship,
				slice, note
				)
			select 
				x.stock_id, x.product_id, x.agent_id,
				x.id_ship,
				x.d_ship, case when x.id_ship is not null then x.value end,
				'MIX2.right', 'отгрузки без выпусков (!products)'
			from #provide x
			where not exists(select 1 from #require where stock_id = x.stock_id and product_id = x.product_id)

		delete from #result where slice = 'mix1'
		-- /***/ SELECT 'STEP2', SUM(Q_MFR) 'Q_MFR', SUM(Q_ISSUE) 'Q_ISSUE', SUM(Q_SHIP) 'Q_SHIP', SUM(Q_ORDER) 'Q_SHIP' FROM #RESULT

	end -- MIX2 = FIFO(MIX1, Отгрузки + Перещения(расход))

	begin
		exec tracer_log @tid, 'MIX3 = FIFO(MIX2, Заказы)'

		delete from #require
		delete from #provide
		update #result set slice = 'mix2' where id_ship is not null -- отгрузки

		insert into #require(
			stock_id, product_id, agent_id,
			d_mfr, d_issue_plan, d_issue, d_ship,
			id_mfr, id_issue, id_ship,
			q_mfr, q_issue, q_ship, value
			)
		select 
			stock_id, product_id, agent_id,
			d_mfr, d_issue_plan, d_issue, d_ship,
			id_mfr, id_issue, id_ship,
			q_mfr, q_issue, q_ship, q_ship
		from #result
		where slice = 'mix2'
		order by stock_id, product_id, d_ship, d_mfr, d_issue

		insert into #provide(
			stock_id, product_id, agent_id, 
			d_order, d_delivery, id_order, value
			)
		select 
			stock_id, product_id, agent_id,
			d_doc, d_delivery, doc_id, quantity
		from v_sdocs_products
		where type_id = 1
			and (@filter_products is null or product_id in (select id from @products))
		order by stock_id, product_id, d_doc, doc_id

		-- FIFO
			exec fifo_clear @fid;

			insert into #result(
				id_mfr, id_issue, id_ship, id_order,
				stock_id, product_id, agent_id,
				d_mfr, d_issue_plan, d_issue, d_ship, d_order, d_delivery,
				q_mfr, q_issue, q_ship, q_order,
				slice, note
				)
			select 
				r.id_mfr, r.id_issue, r.id_ship, p.id_order,
				p.stock_id, p.product_id, p.agent_id,
				r.d_mfr, r.d_issue_plan, r.d_issue, r.d_ship, p.d_order, p.d_delivery,
				--
				case when r.q_mfr is not null then f.value end,
				case when r.q_issue is not null then f.value end,
				f.value, f.value,
				--
				'MIX3', 'FIFO(MIX2, Заказы)'
			from #require r
				join #provide p on
							p.stock_id = r.stock_id 
						and p.product_id = r.product_id
						and p.agent_id = r.agent_id
				cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
			order by r.row_id, p.row_id

		-- left (отгрузки без заказов)
			insert into #result(
				id_mfr, id_issue, id_ship,
				stock_id, product_id, agent_id,
				d_mfr, d_issue_plan, d_issue, d_ship, q_mfr, q_issue, q_ship,
				slice, note
				)
			select
				x.id_mfr, x.id_issue, x.id_ship,
				x.stock_id, x.product_id, x.agent_id,
				x.d_mfr, x.d_issue_plan, x.d_issue, x.d_ship,
				--
				case when x.q_mfr is not null then f.value end,
				case when x.q_issue is not null then f.value end,
				f.value,
				--
				'MIX3.left', 'отгрузки без заказов'
			from dbo.fifo_left(@fid) f
				join #require x on x.row_id = f.row_id
			where f.value > 0

		-- !link
			insert into #result(
				id_mfr, id_issue, id_ship,
				stock_id, product_id, agent_id,
				d_mfr, d_issue_plan, d_issue, d_ship, q_mfr, q_issue, q_ship,
				slice, note
				)
			select
				x.id_mfr, x.id_issue, x.id_ship,
				x.stock_id, x.product_id, x.agent_id,
				x.d_mfr, x.d_issue_plan, x.d_issue, x.d_ship,
				x.q_mfr, x.q_issue, x.q_ship,
				'MIX3.left', 'отгрузки без заказов (!stock,product,agent)'
			from #require x
			where not exists(select 1 from #provide where stock_id = x.stock_id and product_id = x.product_id and agent_id = x.agent_id)

		-- right (заказы без отгрузок)
			insert into #result(id_order, stock_id, product_id, agent_id, d_order, d_delivery, q_order, slice, note)
			select 
				x.id_order, x.stock_id, x.product_id, x.agent_id, x.d_order, x.d_delivery, f.value,
				'MIX3.right', 'заказы без отгрузок'
			from dbo.fifo_right(@fid) f
				join #provide x on x.row_id = f.row_id
			where f.value > 0
		
		-- !link
			insert into #result(id_order, stock_id, product_id, agent_id, d_order, d_delivery, q_order, slice, note)
			select 
				x.id_order, x.stock_id, x.product_id, x.agent_id, x.d_order, x.d_delivery, x.value,
				'MIX3.right', 'заказы без отгрузок (!stock,product,agent)'
			from #provide x
			where not exists(select 1 from #require where stock_id = x.stock_id and product_id = x.product_id and agent_id = x.agent_id)

		delete from #result where slice = 'mix2'
		-- /***/ SELECT 'STEP3', SUM(Q_MFR) 'Q_MFR', SUM(Q_ISSUE) 'Q_ISSUE', SUM(Q_SHIP) 'Q_SHIP', SUM(Q_ORDER) 'Q_SHIP' FROM #RESULT

	end -- MIX3 = FIFO(MIX2, Заказы)

	begin
		exec tracer_log @tid, 'MIX4 = FIFO(MIX1.left, MIX3.right)'

		delete from #require
		delete from #provide

		insert into #require(d_order, d_delivery, id_order, stock_id, product_id, q_order, value)
		select d_order, d_delivery, id_order, stock_id, product_id, q_order, q_order
		from #result
		where slice = 'mix3.right'
		order by product_id, d_order

		update #result
		set slice = 'mix1.left', note = 'Запуски без заказов (last)'
		where id_mfr is not null and (id_order is null and id_ship is null)

		insert into #provide(
			d_mfr, d_issue_plan, d_issue, d_ship,
			id_mfr, id_issue, id_ship,
			stock_id, product_id,
			q_issue, q_ship, value
			)
		select
			d_mfr, d_issue_plan, d_issue, d_ship,
			id_mfr, id_issue, id_ship,
			stock_id, product_id,
			q_issue, q_ship, q_mfr
		from #result
		where slice = 'mix1.left'
		order by product_id, d_mfr, d_issue, d_ship

		-- FIFO
			exec fifo_clear @fid;
			insert into #result(
				id_order, id_mfr, id_issue, id_ship,
				stock_id, product_id, agent_id,
				d_order, d_delivery, d_mfr, d_issue_plan, d_issue, d_ship,
				q_order, q_mfr, q_issue, q_ship,
				slice, note
				)
			select 
				r.id_order, p.id_mfr, p.id_issue, p.id_ship,
				p.stock_id, p.product_id, r.agent_id,
				r.d_order, r.d_delivery, p.d_mfr, p.d_issue_plan, p.d_issue, p.d_ship,
				--
				f.value, f.value, 
				case when p.q_issue is not null then f.value end,
				case when p.q_ship is not null then f.value end,
				--
				'MIX4', 'FIFO(MIX1.left, MIX3.right)'
			from #require r
				join #provide p on p.stock_id = r.stock_id and p.product_id = r.product_id
				cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
			order by r.row_id, p.row_id

		-- left (отгрузки без запусков)
			insert into #result(id_order, stock_id, product_id, agent_id, d_order, d_delivery, q_order, slice, note)
			select
				x.id_order, x.stock_id, x.product_id, x.agent_id, x.d_order, x.d_delivery, f.value,
				'MIX4.left', 'заказы без запусков'
			from dbo.fifo_left(@fid) f
				join #require x on x.row_id = f.row_id
			where f.value > 0

		-- !link
			insert into #result(id_order, stock_id, product_id, agent_id, d_order, d_delivery, q_order, slice, note)
			select
				x.id_order, x.stock_id, x.product_id, x.agent_id, x.d_order, x.d_delivery, x.q_order,
				'MIX4.left', 'заказы без запусков (!products)'
			from #require x
			where not exists(select 1 from #provide where stock_id = x.stock_id and product_id = x.product_id)

		-- right (запуски без отгрузок)
			insert into #result(stock_id, product_id, agent_id, id_mfr, d_mfr, id_issue, d_issue_plan, d_issue, id_ship, d_ship, q_mfr, q_issue, q_ship, slice, note)
			select
				x.stock_id, x.product_id, x.agent_id,
				x.id_mfr, x.d_mfr, x.id_issue, x.d_issue_plan, x.d_issue, x.id_ship, x.d_ship,
				--
				f.value,
				case when x.q_issue is not null then f.value end,
				case when x.q_ship is not null then f.value end,
				--
				'MIX4.right', 'запуски без заказов'
			from dbo.fifo_right(@fid) f
				join #provide x on x.row_id = f.row_id
			where f.value > 0

		-- !link
			insert into #result(stock_id, product_id, agent_id, id_mfr, d_mfr, id_issue, d_issue_plan, d_issue, id_ship, d_ship, q_mfr, q_issue, q_ship, slice, note)
			select 
				stock_id, product_id, agent_id, id_mfr, d_mfr, id_issue, d_issue_plan, d_issue, id_ship, d_ship,
				--
				value, q_issue, q_ship,
				--
				'MIX4.right', 'запуски без заказов (!products)'
			from #provide x
			where not exists(select 1 from #require where stock_id = x.stock_id and product_id = x.product_id)

		delete from #result where slice in ('mix1.left', 'mix3.right')	
		-- /***/ SELECT 'STEP4', SUM(Q_MFR) 'Q_MFR', SUM(Q_ISSUE) 'Q_ISSUE', SUM(Q_SHIP) 'Q_SHIP', SUM(Q_ORDER) 'Q_SHIP' FROM #RESULT

	end -- MIX4 = FIFO(MIX1.left, MIX3.right)

	-- checksum
	begin
		select 
			check_mfr = sum(q_mfr),
			check_issue = sum(q_issue),
			check_ship = sum(q_ship),
			check_order = sum(q_order)
		from (
			select q_mfr, q_issue, q_ship, q_order from (
				select slice, note, 
					sum(q_mfr) q_mfr,
					sum(q_issue) q_issue,
					sum(q_ship) q_ship,
					sum(q_order) q_order
				from #result group by rollup (slice, note)
				) u
			where (slice is null and note is null)
			union all
			select
				(
					select sum(-quantity) from v_sdocs_products where type_id = 2
						and (@filter_products is null or product_id in (select id from @products))
				),
				(
					select sum(-quantity) from (
						select quantity = sum(quantity) from v_sdocs_products where type_id = 3
							and (@filter_products is null or product_id in (select id from @products))
						union all
						select sum(quantity) from v_sdocs_products where type_id = 7 and quantity > 0
							and (@filter_products is null or product_id in (select id from @products))
					) s1
				),
				(
					select sum(-quantity) from (
						select quantity = sum(quantity) from v_sdocs_products where type_id = 4
							and (@filter_products is null or product_id in (select id from @products))
						union all
						select sum(-quantity) from v_sdocs_products where type_id = 7 and quantity < 0
							and (@filter_products is null or product_id in (select id from @products))
					) s4
				),
				(
					select sum(-quantity) from v_sdocs_products where type_id = 1
						and (@filter_products is null or product_id in (select id from @products))
				)
			) u -- CHECKSUM
	end

	begin

		truncate table sdocs_provides

		insert into sdocs_provides(
			stock_id, product_id, 
			id_mfr, id_issue, id_ship, id_order,
			d_mfr, d_issue_plan, d_issue, d_ship, d_order, d_delivery,
			q_mfr, q_issue, q_ship, q_order,
			slice, note
			)
		select
			stock_id, product_id, 
			id_mfr, id_issue, id_ship, id_order,
			d_mfr, d_issue_plan, d_issue, d_ship, d_order, d_delivery,
			q_mfr, q_issue, q_ship, q_order,
			slice, note
		from #result

		update x
		set v_mfr = cast(x.q_mfr * ord.price_rur as decimal(18,2))
		from sdocs_provides x
			left join (
				select doc_id, product_id, sum(value_rur)/nullif(sum(quantity),0) as price_rur
				from sdocs_products
				group by doc_id, product_id
			) ord on ord.doc_id = x.id_order and ord.product_id = x.product_id

		update x
		set v_order = cast(x.q_order * ord.price_rur as decimal(18,2))
		from sdocs_provides x
			join (
				select doc_id, product_id, sum(value_rur)/nullif(sum(quantity),0) as price_rur
				from sdocs_products
				group by doc_id, product_id
			) ord on ord.doc_id = x.id_order and ord.product_id = x.product_id

		-- id_deal, v_paid
			update x
			set id_deal = d.deal_id
			from sdocs_provides x
				join sdocs sd on sd.doc_id = x.id_order
					join deals d on d.number = sd.deal_number

			declare @deals table(deal_id int primary key, value_paid float)
				insert into @deals(deal_id, value_paid)
				select d.deal_id, sum(f.value_rur)
				from findocs# f
					join deals d on d.budget_id = f.budget_id
				where f.article_id = 24
					and exists(select 1 from sdocs_provides where id_deal = d.deal_id)
				group by d.deal_id

			declare @deals_products table(
				row_id int primary key, value_paid float
				)
			insert into @deals_products(row_id, value_paid)
			select x.row_id, x.v_order / nullif(xx.v_order,0) * d.value_paid
			from sdocs_provides x
				join (
					select id_deal, sum(v_order) as v_order from sdocs_provides
					group by id_deal
				) xx on xx.id_deal = x.id_deal
				join @deals d on d.deal_id = x.id_deal

			update x
			set v_paid = xx.value_paid
			from sdocs_provides x
				join @deals_products xx on xx.row_id = x.row_id

		-- status_id
			update sdocs_provides
			set status_id = 
					case
						when id_ship is not null then 4
						when id_issue is not null then 3
						when id_mfr is not null then 2
						when id_order is not null then 1
						else 0
					end

		-- авто-обновление статусов сделок
			update x
			set status_id =
					case
						when exists(select 1 from v_sdocs_provides where id_deal = x.deal_id and q_ship > 0) then 27 -- Дебиторка
						when exists(select 1 from v_sdocs_provides where id_deal = x.deal_id and q_issue > 0) then 26 -- Склад
						when exists(select 1 from v_sdocs_provides where id_deal = x.deal_id and q_mfr > 0) then 25 -- Производство
						-- when exists(select 1 from v_sdocs_provides where id_deal = x.deal_id and q_order > 0) then 24 -- обрабатываем
						else x.status_id
					end
			from deals x
			where x.status_id between 20 and 32

	end -- sdocs_provides

	-- tracer	
		exec tracer_close @tid
		if @trace = 1 exec tracer_view @tid

	e:
	-- clear temp
		exec fifo_clear @fid
		drop table #require, #provide, #result
end
go

-- exec sdocs_provides_calc 1000, @trace = 1
-- select x.D_ISSUE, x.D_SHIP, x.D_MFR, x.D_ORDER from v_sdocs_provides x