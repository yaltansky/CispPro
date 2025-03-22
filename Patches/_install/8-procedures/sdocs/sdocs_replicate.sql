if object_id('sdocs_replicate') is not null drop proc sdocs_replicate
go
-- exec sdocs_replicate @type_id = 5
create proc sdocs_replicate
	@date_from datetime = null,
	@date_to datetime = null,
	@subject_id int = null,
	@type_id int = null,
		/**
		1 - (Клиентские) Заказы
		2 - Запуски
		3 - Выпуски
		4 - Отгрузка
		7 - Перемещения
		**/
	@skip_prepare bit = 0,
	@trace bit = 0
as
begin

	set nocount on;

	set @date_from = isnull(@date_from, '2021-01-01' /* чтобы не реплицировать всё заново */)

	-- prepare
		if @skip_prepare = 0 and object_id('cf.dbo.prepare_products') is not null
			exec cf.dbo.prepare_products @doc_date_from = @date_from, @doc_date_to = @date_to, @subject_id = @subject_id
			
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = 1

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @type_id=', @type_id
			)
		exec tracer_log @tid, @tid_msg

	begin
		create table #sdocs(
			EXTERN_ID VARCHAR(32) PRIMARY KEY,
			DOC_ID INT,
			SUBJECT_ID INT,
			TYPE_ID INT,
			STATUS_ID INT,
			STOCK_ID INT,
			STOCK_NAME VARCHAR(50),
			D_DOC DATETIME,
			D_DELIVERY DATETIME,
			D_ISSUE DATETIME,
			NUMBER VARCHAR(50),
			DEAL_ID INT,
			DEAL_NUMBER VARCHAR(50),
			BUDGET_ID INT,
			AGENT_ID INT,
			AGENT_NAME VARCHAR(250),
			AGENT_DOGOVOR VARCHAR(50),
			CCY_ID CHAR(3),
			CCY_RATE FLOAT,
			VALUE_CCY DECIMAL(18,2),
			VALUE_RUR DECIMAL(18,2),
			NOTE VARCHAR(MAX)
		)

		create table #sdocs_products(
			EXTERN_DOC_ID VARCHAR(32) INDEX IX_EXTERN,
			PRODUCT_ID INT,
			PRODUCT_NAME VARCHAR(500) INDEX IX_NAME,
			UNIT_ID INT,
			UNIT_NAME VARCHAR(20),
			QUANTITY FLOAT,
			PRICE FLOAT,
			PRICE_PURE FLOAT,
			PRICE_PURE_TRF FLOAT,
			NDS_RATIO DECIMAL(18,4),
			VALUE_PURE DECIMAL(18,2),
			VALUE_NDS DECIMAL(18,2),
			VALUE_CCY DECIMAL(18,2),
			VALUE_RUR DECIMAL(18,2),
			NOTE VARCHAR(MAX)
		)
	end -- tables

	begin
		exec tracer_log @tid, 'КЛИЕНТСКИЕ ЗАКАЗЫ'
		exec tracer_log @tid, '    #sdocs'

		insert into #sdocs(
			extern_id, type_id, status_id,
			subject_id, stock_id, stock_name,
			d_doc, d_delivery,
			number, deal_id, deal_number, agent_name,
			ccy_id, value_ccy, value_rur,
			note
			)
		select 
			concat('1.', h.DocId),
			1, -- Заказы
			10, -- Принят
			h.subject_id,
			stocks.stock_id, hx.mfrname,
			h.DocDate, hx.DeliveryDate,
			upper(h.DocNo), 
			case
				when hx.ContractBgID > 180000 then -hx.ContractBgID
				else hx.ContractBgID
			end,
			upper(hx.ContractBgNo),
			hx.CustomerName,
			sd.ccy_id, sd.value_ccy, sd.value_rur,
			h.DocComment
		from cf..doc_prod_baseh h
			join cf..doc_prod_saleh hx on hx.DocId = h.DocId
				left join sdocs_stocks stocks on stocks.name = hx.mfrname
				join (
					select DocId, max(d.CurrencyName) as ccy_id 
						, sum(d.SaleRurT)/nullif(max(d.CurrencyRate),0) as value_ccy
						, sum(d.SaleRurT) as value_rur
					from cf..doc_prod_saled d
					group by DocID
				) sd on sd.DocID = hx.DocID
		where @date_from is null or h.DocDate >= @date_from

		update x
		set budget_id = deals.budget_id
		from #sdocs x
			join deals on deals.deal_id = x.deal_id

		exec tracer_log @tid, '    #sdocs_products'
		insert into #sdocs_products(
			extern_doc_id,
			product_name, unit_name, quantity,
			price, price_pure, price_pure_trf, nds_ratio,
			value_pure, value_nds, value_ccy, value_rur
			)
		select
			concat('1.', d.DocId),
			d.ProductName,
			lower(ltrim(rtrim(d.UnitName))),
			d.Q,
			d.SaleRur / nullif(d.CurrencyRate,0) / nullif(d.Q,0),
			d.SalePc, d.TrfPc, (d.SaleRurT - d.SaleRur) / nullif(d.SaleRur,0),
			d.SaleRur / nullif(d.CurrencyRate,0),
			(d.SaleRurT - d.SaleRur) / nullif(d.CurrencyRate,0),
			d.SaleRurT / nullif(d.CurrencyRate,0),
			d.SaleRurT
		from cf..doc_prod_saled d
			join #sdocs sd on sd.extern_id = concat('1.', d.docid)

		update x
		set deal_id = d.deal_id, budget_id = d.budget_id
		from #sdocs x 
			join deals d on d.number = x.deal_number
		where x.type_id = 1 and x.deal_id is null

	end -- клиентские заказы

	begin
		exec tracer_log @tid, 'ПРОИЗВОДСТВЕННЫЕ ЗАПУСКИ'
		exec tracer_log @tid, '    #sdocs'
		insert into #sdocs(
			extern_id, type_id, status_id,
			subject_id, stock_id, stock_name,
			d_doc, d_issue,
			number, agent_name, agent_dogovor,
			note
			)
		select 
			concat('2.', h.DocId),
			2, -- Запуски
			10, -- Принят
			h.subject_id,
			stocks.stock_id, hx.mfrname,
			h.DocDate, hx.PlanDate,
			upper(h.DocNo), hx.DeliveryName, hx.DeliveryAgreeNo,
			h.DocComment
		from cf..doc_prod_baseh h
			join cf..doc_prod_mfrh hx on hx.DocId = h.DocId
				left join sdocs_stocks stocks on stocks.name = hx.mfrname
		where @date_from is null or h.DocDate >= @date_from

		exec tracer_log @tid, '    #sdocs_products'
		insert into #sdocs_products(
			extern_doc_id,
			product_name, unit_name, quantity, value_pure, value_nds, value_ccy, value_rur
			)
		select
			concat('2.', d.DocId),
			d.ProductName,
			lower(ltrim(rtrim(d.UnitName))),
			d.Q,
			value_pure = d.TrfSumPc + d.MatSumPc,
			value_nds = d.TrfSumPcT + d.MatSumPcT - d.TrfSumPc - d.MatSumPcT,
			value_ccy = d.TrfSumPcT + d.MatSumPcT,
			value_rur = d.TrfSumPcT + d.MatSumPcT
		from cf..doc_prod_mfrd d
			join #sdocs sd on sd.extern_id = concat('2.', d.docid)

	end -- запуски

	begin
		exec tracer_log @tid, 'ПРОИЗВОДСТВЕННЫЕ ВЫПУСКИ (ПОСТУПЛЕНИЯ НА СКЛАД)'
		exec tracer_log @tid, '    #sdocs'
		insert into #sdocs(
			extern_id, type_id, status_id,
			subject_id, stock_id, stock_name,
			d_doc, number, agent_name, agent_dogovor,
			note
			)
		select 
			concat('3.', h.DocId),
			3, -- Выпуски
			10, -- Принят
			h.subject_id,
			stocks.stock_id, hx.mfrname,
			h.DocDate, upper(h.DocNo), hx.DeliveryName, hx.DeliveryAgreeNo,
			h.DocComment
		from cf..doc_prod_baseh h
			join cf..doc_prod_receipth hx on hx.DocId = h.DocId
				left join sdocs_stocks stocks on stocks.name = hx.mfrname
		where @date_from is null or h.DocDate >= @date_from

		exec tracer_log @tid, '    #sdocs_products'
		insert into #sdocs_products(
			extern_doc_id, product_name, unit_name, quantity
			)
		select
			concat('3.', d.DocId), d.ProductName,
			lower(ltrim(rtrim(d.UnitName))),
			d.Q
		from cf..doc_prod_receiptd d
			join #sdocs sd on sd.extern_id = concat('3.', d.docid)

	end -- выпуски

	begin
		exec tracer_log @tid, 'ОТГРУЗКИ КЛИЕНТУ'
		exec tracer_log @tid, '    #sdocs'
		insert into #sdocs(
			extern_id, type_id, status_id,
			subject_id, stock_id, stock_name,
			d_doc, number, agent_name,
			note
			)
		select 
			concat('4.', h.DocId),
			4, -- Отгрузка
			10, -- Принят
			h.subject_id,
			stocks.stock_id, hx.mfrname,
			h.DocDate, upper(h.DocNo), hx.AgentName,
			h.DocComment
		from cf..doc_prod_baseh h
			join (
				select 
					shiph.docid, 
					shiph.AgentName,
					max(shipd.mfrname) as mfrname
				from cf..doc_prod_shiph shiph
					join cf..doc_prod_shipd shipd on shipd.DocID = shiph.DocID
				group by shiph.docid, shiph.AgentName
			) hx on hx.docid = h.docid
			left join sdocs_stocks stocks on stocks.name = hx.mfrname
		where @date_from is null or h.DocDate >= @date_from

		exec tracer_log @tid, '    #sdocs_products'
		insert into #sdocs_products(
			extern_doc_id, product_name, unit_name, quantity,
			price, price_pure, nds_ratio,
			value_pure, value_nds, value_ccy, value_rur
			)
		select
			concat('4.', d.DocId), d.ProductName,
			lower(ltrim(rtrim(d.UnitName))),
			d.Q,
			d.SaleRur / nullif(d.CurrencyRate,0) / nullif(d.Q,0),
			d.SalePc, (d.SaleRurT - d.SaleRur) / nullif(d.SaleRur,0),
			d.SaleRur / nullif(d.CurrencyRate,0),
			(d.SaleRurT - d.SaleRur) / nullif(d.CurrencyRate,0),
			d.SaleRurT / nullif(d.CurrencyRate,0),
			d.SaleRurT
		from cf..doc_prod_shipd d
			join #sdocs sd on sd.extern_id = concat('4.', d.docid)

	end -- отгрузки

	begin
		exec tracer_log @tid, 'ВНУТРЕННИЕ ПЕРЕМЕЩЕНИЯ'
		exec tracer_log @tid, '    #sdocs'
		insert into #sdocs(
			extern_id, type_id, status_id,
			subject_id, stock_id, stock_name,
			d_doc, number
			)
		select 
			concat('7.', h.DocId),
			7, -- Перемещения
			10, -- Принят
			stocks.subject_id,
			stocks.stock_id, h.MfrName,
			hh.DocDate, upper(hh.DocNo)
		from cf..doc_prod_moveh h
			join cf..doc_prod_baseh hh on hh.DocID = h.DocID
			left join sdocs_stocks stocks on stocks.name = h.MfrName
		where @date_from is null or hh.DocDate >= @date_from

		exec tracer_log @tid, '    #sdocs_products'
		insert into #sdocs_products(
			extern_doc_id, product_name, unit_name, quantity,
			price, price_pure, nds_ratio,
			value_pure, value_nds, value_ccy, value_rur
			)
		select
			concat('7.', d.DocId), d.ProductName,
			lower(ltrim(rtrim(d.UnitName))),
			d.Q,
			d.TrfSumPcT / nullif(abs(d.Q),0),
			d.TrfSumPc / nullif(abs(d.Q),0),
			(d.TrfSumPcT - d.TrfSumPc) / nullif(d.TrfSumPc,0),
			d.TrfSumPc,
			d.TrfSumPcT - d.TrfSumPc,
			d.TrfSumPcT,
			d.TrfSumPcT
		from cf..doc_prod_moved d
			join #sdocs sd on sd.extern_id = concat('7.', d.docid)

	end -- внутренние перемещения

	BEGIN TRY
	BEGIN TRANSACTION

		exec tracer_log @tid, 'авто-справочники'
		exec sdocs_replicate;2

		exec tracer_log @tid, 'SDOCS, SDOCS_PRODUCTS'
		update x set doc_id = sd.doc_id
		from #sdocs x
			join sdocs sd on sd.extern_id = x.extern_id

		declare @seed_id int = isnull((select max(doc_id) from sdocs), 0)
		update x
		set doc_id = @seed_id + xx.id
		from #sdocs x
			join (
				select row_number() over (order by (select 0)) as id, extern_id
				from #sdocs
			) xx on xx.extern_id = x.extern_id
		where x.doc_id is null

		select * into #old_sdocs from sdocs
		where (@subject_id is null or subject_id = @subject_id)
			and (@date_from is null or d_doc >= @date_from)
			and (@date_to is null or d_doc <= @date_to)
			and (type_id in (1,2,3,4,7))

		delete from sdocs where doc_id in (select doc_id from #old_sdocs)	
		delete from sdocs where doc_id in (select doc_id from #sdocs) -- могут остаться строки, у которых изменилась дата DocDate

		SET IDENTITY_INSERT SDOCS ON;

			insert into sdocs(		
				extern_id, doc_id,
				subject_id, stock_id, type_id, status_id,
				d_doc, d_delivery, d_issue,
				number, deal_id, deal_number, budget_id, agent_id, agent_dogovor,
				ccy_id, ccy_rate, value_ccy, value_rur,
				note,
				add_mol_id
				)
			select
				x.extern_id, x.doc_id,
				x.subject_id, x.stock_id, x.type_id, x.status_id,
				x.d_doc, x.d_delivery, x.d_issue,
				isnull(old.number, x.number), x.deal_id, x.deal_number, isnull(old.budget_id, x.budget_id), x.agent_id, x.agent_dogovor,
				x.ccy_id, x.ccy_rate, x.value_ccy, x.value_rur,
				x.note,
				-25
			from #sdocs x
				left join #old_sdocs old on old.DOC_ID = x.doc_id

			set @tid_msg = concat('    rows ', @@rowcount, ' inserted')
			exec tracer_log @tid, @tid_msg

		SET IDENTITY_INSERT SDOCS OFF;

		insert into sdocs_products(
			doc_id,
			product_id, unit_id, quantity,
			price, price_pure, price_pure_trf, nds_ratio,
			value_pure, value_nds, value_ccy, value_rur
		)
		select
			h.doc_id,
			product_id, unit_id, quantity,
			price, price_pure, price_pure_trf, nds_ratio,
			d.value_pure, d.value_nds, d.value_ccy, d.value_rur
		from #sdocs_products d
			join #sdocs h on h.extern_id = d.extern_doc_id

		-- map agents
			update x
			set agent_id = pa.agent_id
			from sdocs x
				join #sdocs xp on xp.doc_id = x.doc_id
				join agents a on a.agent_id = x.agent_id
					join agents pa on pa.agent_id = a.main_id
			where x.agent_id <> pa.agent_id

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		exec tracer_log @tid, @err
		raiserror (@err, 16, 3)
	END CATCH

	final:	
	exec drop_temp_table '#sdocs,#sdocs_products,#old_sdocs'

	-- close log	
	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid
	return

	mbr:
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	raiserror('manual break', 16, 1)
end
GO
-- helper: авто-справочники
create proc sdocs_replicate;2
as
begin

  print '    STOCKS'
    declare @seed_stocks int = isnull((select max(stock_id) from sdocs_stocks), 0)
    insert into sdocs_stocks(stock_id, name, subject_id)
    select
      @seed_stocks + row_number() over (order by stock_name),
      stock_name,
      0
    from (
      select distinct 	stock_name
      from #sdocs
      where stock_id is null
        and stock_name is not null
      ) x

    update x
    set stock_id = a.stock_id
    from #sdocs x
      join sdocs_stocks a on a.name = x.stock_name

  print '    AGENTS'
    insert into agents(name, name_print)
    select distinct agent_name, agent_name
    from #sdocs
    where agent_name not in (select name from agents)
      and agent_name <> '-'

    update x
    set agent_id = a.agent_id
    from #sdocs x
      join agents a on a.name = x.agent_name

  print '    PRODUCTS'
    insert into products(name, name_print, status_id)
    select distinct product_name, product_name, 5
    from #sdocs_products x
    where product_id is null
      and not exists(select 1 from products where name = x.product_name)
    
    update x
    set product_id = p.product_id
    from #sdocs_products x
      join products p on p.name = x.product_name

  print '    PRODUCTS_UNITS'
    update #sdocs_products set unit_name = 'шт' where unit_name = '-'

    declare @units_seed int = isnull((select max(unit_id) from products_units), 0) + 1
    insert into products_units(unit_id, name)
    select
      row_number() over (order by unit_name) + @units_seed,
      unit_name
    from (
      select distinct unit_name from #sdocs_products where unit_name is not null
      ) x
    where not exists(select 1 from products_units where name = x.unit_name)

    update x
    set unit_id = u.unit_id
    from #sdocs_products x
      join products_units u on u.name = x.unit_name

end
GO
