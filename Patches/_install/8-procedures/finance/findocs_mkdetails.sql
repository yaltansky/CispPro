if object_id('findocs_mkdetails') is not null drop proc findocs_mkdetails
go
-- exec findocs_mkdetails 1000, 72796, @checkonly = 1
create proc findocs_mkdetails
	@mol_id int,
	@folder_id int,	
	@principal_id int = 9,
	@leave_earlypays bit = 0,
	@checkonly bit = 0,
	@trace bit = 0
as
begin

	set nocount on;

	if @checkonly = 1 set @trace = 1

	declare @tid int; exec tracer_init 'findocs_mkdetails', @trace_id = @tid out, @echo = @trace

	declare @hasResultInputs bit = case when object_id('tempdb.dbo.#resultInputs') is not null then 1 else 0 end 
	declare @hasResultOutputs bit = case when object_id('tempdb.dbo.#resultOutputs') is not null then 1 else 0 end 

	if @hasResultInputs = 0
		exec findocs_mkdetails;2 @folder_id -- prepare findocs.note

	declare @today datetime = dbo.today()

exec tracer_log @tid, '#buffer'
	create table #buffer (findoc_id int primary key, folder_id int)
	declare @folder hierarchyid, @keyword varchar(50)
	select @folder = node, @keyword = keyword from objs_folders where folder_id = @folder_id

	-- #buffer
		insert into #buffer (findoc_id, folder_id)
		select fd.obj_id, max(fd.folder_id)
		from objs_folders_details fd
			join (
				select folder_id from objs_folders where keyword = @keyword and node.IsDescendantOf(@folder) = 1
					and is_deleted = 0
			) f on f.folder_id = fd.folder_id
		where fd.obj_type = 'fd'
		group by fd.obj_id

	-- check access
		declare @for_update bit = case when @hasResultInputs = 1 then 0 else 1 end
		exec findocs_mkdetails;3 @mol_id = @mol_id, @for_update = @for_update
		if @@error <> 0 return

	-- @principal_pred_id	
		declare @principal_pred_id int = (select pred_id from subjects where subject_id = @principal_id)

exec tracer_log @tid, '#budgets'
	create table #budgets(
		project_id int,
		budget_id int,
		d_doc datetime default(0),
		deal_product_id int default(0),
		article_id int,
		deal_nds_ratio float,
		value_plan decimal(18,2), value_nds decimal(18,2)
		)
		create unique index ix_deals_budgets on #budgets(budget_id, d_doc, deal_product_id, article_id)

	-- набор бюджетов
	create table #buf_budgets(project_id int index ix_project, budget_id int primary key, type_id int, vendor_id int)
		insert into #buf_budgets(project_id, budget_id, type_id, vendor_id)
		select distinct b.project_id, f.budget_id, p.type_id, isnull(pc.vendor_id, d.vendor_id)
		from findocs# f
			join budgets b on b.budget_id = f.budget_id
				join projects p on p.project_id = b.project_id
					left join deals d on d.deal_id = p.project_id
					left join projects_contracts pc on pc.project_id = p.project_id
		where f.findoc_id in (select findoc_id from #buffer)
			and f.value_rur > 0

	-- плановые затраты (сделки)
	insert into #budgets(project_id, budget_id, d_doc, deal_product_id, article_id, deal_nds_ratio, value_plan, value_nds)
	select bb.project_id, bb.budget_id, isnull(db.task_date, 0), db.deal_product_id, db.article_id, max(d.nds_ratio), sum(db.value_bds), sum(db.value_nds)
	from deals_budgets_products db
		join deals d on d.deal_id = db.deal_id
		join #buf_budgets bb on bb.project_id = db.deal_id
	where db.value_bds < 0 -- затраты (план)
	group by bb.project_id, bb.budget_id, db.task_date, db.deal_product_id, db.article_id


	-- плановые затраты (проекты, график затрат)
	insert into #budgets(project_id, budget_id, d_doc, article_id, value_plan, value_nds)
	select bb.project_id, bb.budget_id, isnull(per.date_end, 0), isnull(db.article_id,0), sum(db.plan_rur), null
	from #buf_budgets bb
		left join budgets_plans db on bb.budget_id = db.budget_id and db.has_childs = 0
			left join budgets_periods per on per.budget_id = db.budget_id and per.budget_period_id = db.budget_period_id and per.is_deleted = 0
	where bb.type_id <> 3 -- проекты
		and isnull(db.plan_rur,-1) < 0 -- затраты (план)
	group by bb.project_id, bb.budget_id, isnull(per.date_end, 0), db.article_id

	/* а можно использовать итоговый план:
	insert into #budgets(project_id, budget_id, article_id, value_plan, value_nds)
	select bb.project_id, bb.budget_id, isnull(per.date_end, 0), isnull(db.article_id,0), sum(db.plan_dds), sum(db.plan_dds - db.plan_bdr)
	from #buf_budgets bb
		 left join budgets_totals db on bb.budget_id = db.budget_id
	where bb.type_id <> 3 -- проекты
		and isnull(db.plan_dds, -1) < 0 -- затраты (план)
	group by bb.project_id, bb.budget_id, db.article_id
	*/

exec tracer_log @tid, '#require (БС)'
	create table #require(
		row_id int identity primary key,
		project_id int index ix_project,
		budget_id int index ix_budget,
		d_doc date,
		deal_product_id int,
		article_id int,
		value float,
		value_nds float
		)

	insert into #require(project_id, budget_id, d_doc, deal_product_id, article_id, value, value_nds)
	select
		project_id, budget_id, d_doc, deal_product_id, article_id, -sum(value), -sum(value_nds)
	from (
		select 
			db.project_id, 
			db.budget_id,
			db.d_doc,
			isnull(
				case when db.deal_nds_ratio = 0 then ap.sort_nds0 else ap.sort_std end,
				9999) as sort_id,
			db.deal_product_id,
			db.article_id, 
			a.name,
			db.value_plan as value,
			db.value_nds
		from #budgets db
			join bdr_articles a on a.article_id = db.article_id
				left join deals_articles_priority ap on ap.article_short_name = isnull(a.short_name, a.name)
		) x
	group by x.project_id, x.budget_id, x.d_doc, x.sort_id, x.deal_product_id, x.article_id, x.name
	-- FIFO: порядок статей бюджета (для связи с входящими платежами)
	order by x.project_id, x.budget_id, x.d_doc, x.sort_id, x.deal_product_id, x.name

	-- select sum(value_nds) from #require where budget_id = 298890
	-- return

exec tracer_log @tid, '#provide (приходы)'
	create table #provide(
		row_id int identity primary key,		
		vendor_id int, project_id int, budget_id int, findoc_id int, d_doc datetime,
		value float
		)
	-- учитываем приходы по БС
	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')
	insert into #provide(vendor_id, project_id, budget_id, findoc_id, d_doc, value)
	select bb.vendor_id, bb.project_id, bb.budget_id, f.findoc_id, f.d_doc, f.value_rur
	from findocs# f
		join #buf_budgets bb on bb.budget_id = f.budget_id
	where f.value_rur > 0
		and (@principal_id is null or isnull(f.agent_id,0) <> @principal_pred_id) -- кроме поступлений от Принципала
		and (
			f.article_id = 24 -- приходы по фиксированной статье!
			or f.account_id in (select account_id from findocs_accounts where name = @vat_refund)
			)
	-- FIFO: порядок входящих оплат (для связи с планами бюджета)
	order by bb.budget_id, f.d_doc, f.findoc_id


	-- excludes (применяем исключения только при "окрашивании" исходящих платежей)
	if @hasResultInputs = 0
	begin
		declare @folders table(folder_id int primary key)
			insert into @folders(folder_id) select distinct folder_id from objs_folders
			where keyword = @keyword and is_deleted = 0
				and node.IsDescendantOf(@folder) = 1

		delete x
		from #provide x
			join fin_goals_meta_excludes ex on ex.budget_id = x.budget_id
		where ex.folder_id in (select folder_id from @folders)
	end

	-- проверка переплаты по бюджетам
	if @trace = 1
		select 'переплата по бюджетам', budget_id, sum(value) as diff_req_provide
		from (
			select budget_id, value from #require x
			union all
			select budget_id, -value from #provide
			) u
		group by budget_id
		having sum(value) < -0.02

/*****************************
** ОКРАШИВАЕМ ВХОДЯЩИЕ ПЛАТЕЖИ
*****************************/
exec tracer_log @tid, '#paysInputs'
	declare @fid uniqueidentifier set @fid = newid()

	-- @paysInputsFull
	declare @paysInputsFull table(
		row_id int identity,
		d_doc date, findoc_id int, vendor_id int, budget_id int, deal_product_id int, article_id int,
		value float, value_nds float
		)

	insert into @paysInputsFull(
		d_doc, findoc_id, vendor_id, budget_id, deal_product_id, article_id, value, value_nds
		)
	select 
		p.d_doc,
		p.findoc_id,
		p.vendor_id,
		p.budget_id,
		r.deal_product_id,
		r.article_id,
		f.value,
		r.value_nds * f.value / nullif(r.value, 0)
	from #require r
		join #provide p on p.project_id = r.project_id
		cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
	order by r.row_id, p.row_id

	-- @paysInputs
	declare @paysInputs table(
		-- ВАЖНО: это поле необходимо для гарантии ORDER BY, что приоритетно для FIFO
		-- Иначе: нужно использовать технику insert into xxx(...) exec ...
		row_id int primary key,
		d_doc date, findoc_id int, vendor_id int, budget_id int, article_id int,
		value float, value_nds float
		)

	insert into @paysInputs(row_id, d_doc, findoc_id, vendor_id, budget_id, article_id, value, value_nds)
	select min(row_id), d_doc, findoc_id, vendor_id, budget_id, article_id, sum(value), sum(value_nds)
	from @paysInputsFull
	group by d_doc, findoc_id, vendor_id, budget_id, article_id

	-- select * from #require where budget_id = 298890
	-- select a.name, i.[value], i.value_nds from @paysinputs i
	-- 	join bdr_articles a on a.article_id = i.article_id
	-- where budget_id = 298890 
	-- order by i.row_id
	-- return

	declare @max_d_doc date = (
		select max(d_doc) from findocs where findoc_id in (select findoc_id from #buffer)
		)

	-- #paysInputs (by buffer)
	create table #paysInputsFull(
		row_id int identity primary key,
		d_doc date, folder_id int, vendor_id int, budget_id int, deal_product_id int, article_id int, findoc_id int,
		value float, value_nds float		
		)
		create index ix_paysInput on #paysInputsFull(folder_id, vendor_id)

	insert into #paysInputsFull(
		d_doc, folder_id, vendor_id, budget_id, deal_product_id, article_id, findoc_id, value, value_nds
		)
	select 
		x.d_doc, buf.folder_id, x.vendor_id, x.budget_id, x.deal_product_id, x.article_id, x.findoc_id,
		sum(x.value), sum(x.value_nds)
	from @paysInputsFull x
		left join #buffer buf on buf.findoc_id = x.findoc_id
	where (
		   (@leave_earlypays = 1)
		or (@leave_earlypays = 0 and buf.findoc_id is not null)
		)
		and x.d_doc <= @max_d_doc
	group by x.d_doc, buf.folder_id, x.vendor_id, x.budget_id, x.deal_product_id, x.article_id, x.findoc_id
	order by x.vendor_id, x.d_doc, x.budget_id, x.deal_product_id

	create table #paysInputs(
		row_id int identity primary key,
		d_doc date, folder_id int, vendor_id int, budget_id int, article_id int, findoc_id int,
		value float, value_nds float		
		)
		create index ix_paysInput on #paysInputs(folder_id, vendor_id)

	insert into #paysInputs(d_doc, folder_id, vendor_id, budget_id, article_id, findoc_id, value, value_nds)
	select d_doc, folder_id, vendor_id, budget_id, article_id, findoc_id, sum(value), sum(value_nds)
	from #paysInputsFull
	group by d_doc, folder_id, vendor_id, budget_id, article_id, findoc_id
	order by min(row_id)

	if @hasResultInputs = 1
	begin
		insert into #resultInputs(
			row_id,
			d_doc, folder_id, vendor_id, budget_id, deal_product_id, article_id, findoc_id, value, value_nds
			)
		select row_id, d_doc, folder_id, vendor_id, budget_id, deal_product_id, article_id, findoc_id, value, value_nds
		from #paysInputsFull
		
		UNION ALL -- остатки приходов
		select p.row_id, p.d_doc, 0, p.vendor_id, p.budget_id, 0,
			-10, -- <ПЕРЕПЛАТА>
			p.findoc_id, fi.value, null
		from #provide p
			join dbo.fifo_right(@fid) fi on fi.row_id = p.row_id
			join #buffer buf on buf.findoc_id = p.findoc_id
		where abs(fi.value) >= 0.001

		if @hasResultOutputs = 0 goto finish
	end

	-- проверяем, что все приходы получили детализацию
	if @trace = 1 and exists(select 1 from dbo.fifo_right(@fid) where abs(value) > 0.05)
		select row_id, value as value_input_fifo_right from dbo.fifo_right(@fid) where abs(value) > 0.05

/********************************************
** УЧЁТ ФИКСИРОВАННОЙ ДЕТАЛИЗАЦИИ (ИСХОДЯЩИХ)
********************************************/
	-- @paysOutput
	declare @paysOutput table(
		row_id int identity, -- для FIFO
		findoc_id int, vendor_id int, budget_id int, article_id int,
		value float
		)

	insert into @paysOutput(findoc_id, vendor_id, budget_id, article_id, value)
	select f.findoc_id, bb.vendor_id, f.budget_id, f.article_id, -f.value_rur
	from findocs# f
		join #buffer buf on buf.findoc_id = f.findoc_id
		join #buf_budgets bb on bb.budget_id = f.budget_id
	where f.value_rur < 0
		and f.fixed_details = 1
	order by bb.vendor_id, f.d_doc, f.budget_id

	-- @paysDummy
	declare @paysDummy table(row_id int identity, findoc_id int, vendor_id int, budget_id int, article_id int, value float)

	exec fifo_clear @fid

	insert into @paysDummy(findoc_id, vendor_id, budget_id, article_id, value)
	select
		p.findoc_id,
		r.vendor_id,
		r.budget_id,
		r.article_id,
		f.value
	from @paysInputs r
		join #buffer buf on buf.findoc_id = r.findoc_id
		join @paysOutput p on p.vendor_id = r.vendor_id and p.budget_id = r.budget_id and p.article_id = r.article_id
		cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
	order by r.row_id, p.row_id

	-- в результате в приходах осталось 
	update x set value = l.value
	from @paysInputs x
		join dbo.fifo_left(@fid) l on l.row_id = x.row_id

	-- обновляем #paysInputs с учётом детализации
	delete from #paysInputs;
	insert into #paysInputs(
		d_doc, folder_id, vendor_id, budget_id, article_id, findoc_id, value
		)
	select 
		x.d_doc, buf.folder_id, x.vendor_id, x.budget_id, x.article_id, x.findoc_id, sum(x.value)
	from @paysInputs x
		join #buffer buf on buf.findoc_id = x.findoc_id		
	group by x.d_doc, buf.folder_id, x.vendor_id, x.budget_id, x.article_id, x.findoc_id
	-- FIFO: порядок входящих платежей (для связи с исходящими платежами)
	order by x.vendor_id, x.d_doc, x.budget_id

exec tracer_log @tid, '#paysOutput'
	create table #paysOutput(row_id int identity, folder_id int, vendor_id int, findoc_id int, d_doc datetime, value float, value_old float, vendor_name varchar(50))
		create index ix_paysOutput on #paysOutput(folder_id, vendor_id)

	insert into #paysOutput(folder_id, findoc_id, d_doc, value, value_old) 
	select buf.folder_id, f.findoc_id, f.d_doc, -f.value_rur, -f.value_rur
	from findocs f
		join #buffer buf on buf.findoc_id = f.findoc_id
	where f.value_rur < 0		
		and (@principal_id is null or f.agent_id = @principal_pred_id)
		and isnull(f.fixed_details,0) = 0
	-- FIFO: порядок исходящих платежей (для связи с входящими платежами)
	order by buf.folder_id, f.d_doc, f.findoc_id

	declare @index1 int, @index2 int
	update x
	set @index1 = charindex('(', f.note),
		@index2 = charindex(')', f.note),
		vendor_name = 
			case
				when @index1 > 0 and @index2 > @index1 then	ltrim(rtrim(substring(f.note, @index1 + 1, @index2 - @index1 - 1)))
			end
	from #paysOutput x
		join findocs f on f.findoc_id = x.findoc_id
	
	update x set vendor_id = subject_id
	from #paysOutput x
		join subjects on short_name = vendor_name

	if exists(select 1 from #paysOutput where vendor_id is null)
		and @hasResultInputs = 0
	begin
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

		delete from objs_folders_details where folder_id = @buffer_id		
		
		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select distinct @buffer_id, 'FD', findoc_id, @mol_id
		from #paysOutput where vendor_id is null

		if @trace = 1 select 'Не идентифицирована площадка', * from #paysOutput where vendor_id is null

		raiserror('Есть исходящие платежи (помещены в буфер), в которых не удалось идентифицировать площадку (по комментарию типа ...(<название площадки>)...).', 11, 0)
		return
	end

	if @trace = 1 and @checkonly = 0
	begin
		select vendor_id, cast(sum(value) as decimal) as v_diff_input_output
		from (
			select vendor_id, value from #paysInputs
			union all
			select vendor_id, -value from #paysOutput
			) u
		group by vendor_id
		having abs(sum(value)) > -0.01
	end

	--select vendor_id, sum(value) as v_input from #paysInputs group by vendor_id
	--select vendor_id, sum(value) as v_output from #paysOutput group by vendor_id
	--return

/******************************
** ОКРАШИВАЕМ ИСХОДЯЩИЕ ПЛАТЕЖИ
******************************/
exec tracer_log @tid, 'STEP 1: Распределение FIFO с учётом контекста [папка, площадка]'
	exec fifo_clear @fid

	delete from @paysOutput;
	insert into @paysOutput(findoc_id, vendor_id, budget_id, article_id, value)
	select
		p.findoc_id,
		r.vendor_id,
		r.budget_id,
		r.article_id,
		-f.value
	from #paysInputs r
		join #paysOutput p on p.folder_id = r.folder_id and p.vendor_id = r.vendor_id
		cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
	order by r.row_id, p.row_id

	-- #result
	select findoc_id, vendor_id, budget_id, article_id, sum(value) as value
	into #result
	from @paysOutput
	group by findoc_id, vendor_id, budget_id, article_id
	
	update x
	set value = r.value
	from #paysInputs x
		join dbo.fifo_left(@fid) r on r.row_id = x.row_id
	
	delete from #paysInputs where value = 0

	update x
	set value = r.value
	from #paysOutput x
		join dbo.fifo_right(@fid) r on r.row_id = x.row_id

-- окончательные остатки от оплат относим на НЕ РАЗСНЕСЕНО
	insert into #result(findoc_id, budget_id, article_id, value)
	select findoc_id,
		33, -- Бж_Текущий
		0, -- НЕ РАЗСНЕСЕНО
		-value
	from #paysOutput
	where isnull(value,0) >= 0.01

	-- check of #paysOutput
	if @trace = 1
	begin
		if (select sum(value) from #result where budget_id = 33) is not null
			select sum(value) as v_undefined from #result where budget_id = 33 -- НЕ РАЗСНЕСЕНО
			
		select *, cast(v_out - v_out_fifo as decimal) as v_diff
		from (
			select
				(select sum(value_old) from #paysoutput) as v_out,
				(select sum(-value) from #result) as v_out_fifo
			) v
	end

	if @hasResultOutputs = 1
	begin
		insert into #resultOutputs(findoc_id, vendor_id, budget_id, article_id, value)
		select findoc_id, vendor_id, budget_id, article_id, value
		from #result		
	end

	if @hasResultInputs = 1 or @hasResultOutputs = 1
	begin
		goto finish
	end

	declare @MAX_BUFFER_SIZE int = 100
	if @mol_id not in (700, 1000) and (select count(*) from #buffer) > @MAX_BUFFER_SIZE
	begin
		raiserror('Расчёт с количеством оплат > %d доступен только администратору базы данных.', 16, 1, @MAX_BUFFER_SIZE)
		return
	end

	if @checkonly = 1 goto finish

exec tracer_log @tid, 'generate findocs_details'
	BEGIN TRY
	BEGIN TRANSACTION

		delete from findocs_details where findoc_id in (select findoc_id from #result)

		insert into findocs_details(
			findoc_id, budget_id, article_id, value_ccy, value_rur,
			update_date, update_mol_id
			)
		select 
			findoc_id, budget_id, article_id, value, value,
			getdate(), @mol_id
		from #result

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH

	declare @d_doc datetime = (select max(d_doc) from findocs where findoc_id in (select findoc_id from #result))
	exec deals_credits_calc @mol_id = @mol_id, @principal_id = @principal_id, @d_doc = @d_doc

	finish:
		exec fifo_clear @fid
		exec drop_temp_table '#buffer,#buf_budgets,#budgets,#require,#provide,#paysInputs,#paysOutput,#result'

		exec tracer_close @tid
	--if @trace = 1 exec tracer_view @tid
end
go
-- helper: нормализация FINDOCS.NOTE по принадлежности к площадке
create proc findocs_mkdetails;2
	@folder_id int
as
begin

	set nocount on;

	-- #buffer
		create table #buffer (findoc_id int primary key)
		insert into #buffer exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'FD'

	-- #paysOutput
		create table #checkOutput(findoc_id int primary key, article_id int, vendor_id int, vendor_name varchar(250), note varchar(max))

		insert into #checkOutput(findoc_id, article_id, note) 
		select f.findoc_id, f.article_id, f.note
		from findocs f
			join #buffer buf on buf.findoc_id = f.findoc_id
		where f.value_rur < 0

		declare @index1 int, @index2 int
		update x
		set @index1 = charindex('(', note),
			@index2 = charindex(')', note),
			vendor_name = 
				case
					when @index1 > 0 and @index2 > @index1 then	ltrim(rtrim(substring(note, @index1 + 1, @index2 - @index1 - 1)))
				end
		from #checkOutput x
		
		update x set vendor_id = subject_id
		from #checkOutput x
			join subjects on short_name = vendor_name

		-- отсекаем оплаты, которые уже нормализованы
		delete from #checkOutput where vendor_id is not null

		-- 1. По статье оплаты
		update x
		set vendor_name = subjects.short_name
		from #checkOutput x
			join bdr_articles a on a.article_id = x.article_id
				join subjects on subjects.subject_id = a.subject_id

		-- 2. По детализации

			-- если детализация относится к нескольким площадкам (а это - ошибка!)
			select fd.findoc_id, subjects.short_name as vendor_name, sum(fd.value_rur) as value
			into #fd_tmp
			from findocs_details fd
				join #checkoutput c on c.findoc_id = fd.findoc_id
				join bdr_articles a on a.article_id = fd.article_id
					join subjects on subjects.subject_id = a.subject_id
			group by fd.findoc_id, subjects.short_name

			-- ... то берём площадку с максимальной суммой
			select x.findoc_id, x.vendor_name
			into #fd
			from #fd_tmp x
				join (
					select findoc_id, vendor_name, max(value) as max_value
					from #fd_tmp
					group by findoc_id, vendor_name
				) xx on xx.findoc_id = x.findoc_id and xx.vendor_name = x.vendor_name and xx.max_value = x.value

		update x
		set vendor_name = xx.vendor_name
		from #checkOutput x
			join #fd xx on xx.findoc_id = x.findoc_id

	-- Нормализуем примечание
		update x
		set note = concat('(', xx.vendor_name, ') ', x.note)
		from findocs x
			join #checkOutput xx on xx.findoc_id = x.FINDOC_ID
		where xx.vendor_name in (select short_name from subjects where is_vendor = 1)

end
go
-- helper: check allow update
create proc findocs_mkdetails;3
	@mol_id int,
	@for_update bit
as
begin

	-- @objects by reglament
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id, @for_update = @for_update
	-- @subjects
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	-- check
	if exists(
		select 1 from findocs
		where findoc_id in (select findoc_id from #buffer)
			and subject_id not in (select subject_id from @subjects)
		)
	begin
		raiserror('У Вас нет доступа к чтению/изменению оплат в буфере в соответствии с правами на субъект учёта.', 16, 1)
	end

end
go
