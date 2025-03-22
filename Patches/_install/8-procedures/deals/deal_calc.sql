if object_id('deal_calc') is not null drop procedure deal_calc
go
/*
	declare @ids as app_pkids; insert into @ids select deal_id from deals
	exec deal_calc @ids = @ids
*/
create proc deal_calc
	@mol_id int = -25,
	@deal_id int = null,	
	@ids app_pkids readonly,
	@ifnoexists bit = 0,
	@tid int = null,
	@trace bit = 0
as
begin
	
	set nocount on;

	if @ifnoexists = 1 and exists(select 1 from deals_budgets where deal_id = @deal_id)
	begin
		return -- nothing todo
	end

	declare @local_tid int

	if @tid is null
	begin
		exec tracer_init 'deal_calc', @trace_id = @tid out, @echo = @trace
		set @local_tid = @tid
	end

	declare @manager_id int = (select manager_id from deals where deal_id = @deal_id)

-- #ids_deal_calc		
	create table #ids_deal_calc(deal_id int primary key)

	if @deal_id is not null insert into #ids_deal_calc values(@deal_id)
	else insert into #ids_deal_calc select id from @ids
	
	declare @TASK_NDS_NAME varchar(50) = 'Окончательный расчет';
	declare @TASK_BONUS_NAME varchar(50) = 'Окончательный расчет';

BEGIN TRY
BEGIN TRANSACTION
	
exec tracer_log @tid, '    Формирование разделов бюджета'
	if @deal_id is not null exec deal_calc;2 @deal_id = @deal_id, @tid = @local_tid

exec tracer_log @tid, '    Обновить знак доходы/расходы'
	update x
	set value_bdr = a.direction * abs(value_bdr),
		value_nds = a.direction * abs(value_nds),
		value_bds = a.direction * abs(value_bds)
	from deals_budgets x
		join bdr_articles a on a.article_id = x.article_id
	where x.deal_id in (select deal_id from #ids_deal_calc)

exec tracer_log @tid, '    Авто-mapping article_id by subject_id'
	-- articles by subject
	update x
	set article_id = a2.article_id
	from deals_budgets x
		join deals xx on xx.deal_id = x.deal_id
			join #ids_deal_calc ids on ids.deal_id = xx.deal_id
		join bdr_articles a on a.article_id = x.article_id
			join bdr_articles a2 on a2.short_name = a.short_name and a2.subject_id = xx.vendor_id
	where x.is_automap = 1
		
	update x
	set article_id = a2.article_id
	from deals_costs x
		join deals xx on xx.deal_id = x.deal_id
			join #ids_deal_calc ids on ids.deal_id = xx.deal_id
		join bdr_articles a on a.article_id = x.article_id
			join bdr_articles a2 on a2.short_name = a.short_name and a2.subject_id = xx.vendor_id
	where x.is_automap = 1

/*
** РАСЧЁТ ЦЕНОВОЙ ПРЕМИИ И НДС
*/
begin

	delete from deals_budgets
	where deal_id in (select deal_id from #ids_deal_calc)
		and type_id = 4

exec tracer_log @tid, '    РАСЧЁТ "ЦЕНОВАЯ ПРЕМИЯ"'
	create table #b_sum(deal_id int primary key, nds_ratio float, value_nds float, value_bdr float, value_bds float)

	insert into #b_sum(deal_id, nds_ratio, value_bdr, value_bds)
	select db.deal_id, nds.nds_ratio, sum(value_bdr), sum(value_bds)
	from deals_budgets db
		join #ids_deal_calc ids on ids.deal_id = db.deal_id
		join (
			select deal_id, max(nds_ratio) as nds_ratio
			from deals_products
			group by deal_id, product_id
		) nds on nds.deal_id = db.deal_id	
	group by db.deal_id, nds.nds_ratio

	-- @articles
	declare @articles table(deal_id int, article_id int, short_name varchar(30), ratio float)

		insert into @articles(deal_id, article_id, short_name)
		select d.deal_id, a.article_id, a.short_name from deals d join #ids_deal_calc xd on xd.deal_id = d.deal_id
			join bdr_articles a on a.short_name = 'ценовая премия' and isnull(a.subject_id,0) = 0

		insert into @articles(deal_id, article_id, short_name, ratio)
		select d.deal_id, a.article_id, a.short_name, 
			case 
				when isnull(d.spec_date, d.d_doc) >= '2020-06-23' then 0.1 
			end
		from deals d join #ids_deal_calc xd on xd.deal_id = d.deal_id
			join bdr_articles a on a.short_name = 'дополнительное вознаграждение' and isnull(a.subject_id,0) = 0

		insert into @articles(deal_id, article_id, short_name, ratio)
		select d.deal_id, a.article_id, a.short_name, 0.2
		from deals d join #ids_deal_calc xd on xd.deal_id = d.deal_id
			join bdr_articles a on a.short_name = 'доп вознаграждение резерв' and isnull(a.subject_id,0) = 0
		where isnull(d.spec_date, d.d_doc) >= '2020-06-23'

	declare @deals_budgets table(
		deal_id int index ix_deal,
		type_id int,
		task_id int, 
		article_id int,
		value_bdr float,
		value_nds float,
		value_bds float,
		has_profit bit default 1
		)
	insert into @deals_budgets(deal_id, type_id, task_id, article_id, value_bdr, value_nds, value_bds)
	select
		deal_id, type_id, task_id,
		article_id,
		value_bdr * article_ratio,
		value_bdr * nds_ratio * article_ratio,
		value_bdr * (1 + nds_ratio) * article_ratio
	from (
		select 
			d.deal_id,
			4 as type_id, -- итоговый бюджет
			t.task_id,
			a.article_id,
			-b.value_bdr as value_bdr,
			nds_ratio = 
				case
					when a.short_name = 'Ценовая премия' then b.nds_ratio
					else 0.2
				end,
			article_ratio = 
				case
					when a.short_name = 'Ценовая премия' then 0.7
					else isnull(a.ratio, 0.3)
				end 			
		from projects_tasks t
			join deals d on d.deal_id = t.project_id
				join #ids_deal_calc xd on xd.deal_id = d.deal_id
				join #b_sum b on b.deal_id = d.deal_id
				join @articles a on a.deal_id = d.deal_id
		where t.name = @TASK_BONUS_NAME
		) x

	-- Возмещение скидки
	declare @article1_id int = (select top 1 article_id from bdr_articles where short_name = 'возмещение скидки' and isnull(subject_id,0) = 0)
	update @deals_budgets set has_profit = 0, article_id = @article1_id
	where deal_id in (select deal_id from @deals_budgets where value_bds > 0)

	-- articles by subject
	update x
	set article_id = a2.article_id
	from @deals_budgets x
		join deals xx on xx.deal_id = x.deal_id
		join bdr_articles a on a.article_id = x.article_id
			join bdr_articles a2 on a2.short_name = a.short_name and a2.subject_id = xx.vendor_id

	insert into deals_budgets(deal_id, type_id, task_id, article_id, value_bdr, value_nds, value_bds)
	select deal_id, type_id, task_id, article_id, sum(value_bdr), sum(value_nds), sum(value_bds)
	from @deals_budgets
	group by deal_id, type_id, task_id, article_id

exec tracer_log @tid, '    РАСЧЁТ "НДС"'
	delete from #b_sum;

	insert into #b_sum(deal_id, value_nds)
	select x.deal_id, sum(value_nds)
	from deals_budgets x
		join #ids_deal_calc ids on ids.deal_id = x.deal_id	
	group by x.deal_id

	insert into deals_budgets(deal_id, type_id, task_id, article_id, value_bdr, value_nds, value_bds)
	select d.deal_id, 4,
		t.task_id,		
		isnull(a.article_id, a2.article_id),
		0, -b.value_nds, -b.value_nds
	from projects_tasks t
		join deals d on d.deal_id = t.project_id and t.name = @TASK_NDS_NAME
			join #ids_deal_calc xd on xd.deal_id = d.deal_id
			-- articles by subject
			left join bdr_articles a on a.short_name = 'НДС' and a.subject_id = d.vendor_id
			left join bdr_articles a2 on a2.short_name = 'НДС' and isnull(a2.subject_id, 0) = 0 -- если не удалось найти статью по D.VENDOR_ID
		join #b_sum b on b.deal_id = d.deal_id
	-- where b.value_nds <> 0

	-- неточность округления относим на ценовую премию
	update x
	set value_bds = x.value_bds + isnull(xx.round_bds,0)
	from deals_budgets x
		join #b_sum b on b.deal_id = x.deal_id
		join (
			select deal_id, -sum(value_bds) as round_bds
			from deals_budgets
			group by deal_id
			having abs(sum(value_bds)) < 1
		) xx on xx.deal_id = x.deal_id
		join bdr_articles a on a.article_id = x.article_id
			and a.short_name = 'Ценовая премия'

end

/*
** ЕСЛИ НЕТ КАЛЬКУЛЯЦИИ ИЛИ КАЛЬКУЛЯЦИЯ С ОШИБКОЙ, ТО ЦЕНОВУЮ ПРЕМИЮ НЕ НАЧИСЛЯЕМ
*/
begin
	create table #bad_costs(deal_id int primary key)
	
	-- ошибка в калькуляции
	insert into #bad_costs(deal_id)
	select u.deal_id
	from (
		select deal_id, quantity * isnull(price_transfer_pure,0) as value from deals_products
		union all
		select deal_id, -isnull(value_bdr,0) from deals_costs
		) u
		join #ids_deal_calc ids on ids.deal_id = u.deal_id
	group by u.deal_id
	having abs(sum(value)) >= 10.00

	-- калькуляция отсутствует
	insert into #bad_costs(deal_id)
	select u.deal_id
	from deals u
		join #ids_deal_calc ids on ids.deal_id = u.deal_id
	where not exists(select 1 from deals_costs where deal_id = u.deal_id and isnull(value_bdr,0) <> 0)
		and not exists(select 1 from #bad_costs where deal_id = u.deal_id)

	-- Очищаем итоговый бюджет, если есть проблемы с калькуляцией
	delete from deals_budgets
	where type_id = 4
		and deal_id in (select deal_id from #ids_deal_calc)
		and deal_id in (select deal_id from #bad_costs)

	insert into deals_budgets(deal_id, task_id, article_id, type_id, value_bdr, value_nds, value_bds)
	select deal_id, max(task_id),
		0, -- НЕ РАЗНЕСЕНО
		4, -- отнесём формально к окончательному расчёту
		-sum(value_bdr), -sum(value_nds), -sum(value_bds)
	from deals_budgets
	where deal_id in (select deal_id from #ids_deal_calc)
		and deal_id in (select deal_id from #bad_costs)
	group by deal_id

	delete x from deals_budgets x
	where deal_id in (select deal_id from #ids_deal_calc)
		and (
			type_id in (4)
			and isnull(x.value_bdr,0) = 0 and isnull(x.value_nds,0) = 0 and isnull(x.value_bds, 0) = 0
			)

	-- выдаём предупреждение (только для отладки)
	if exists(select 1 from #bad_costs) begin
		select 'Ошибка калькуляции', deal_id from #bad_costs
		print '*** DEAL_CALC/WARNING: Отсутствует калькуляция или калькуляция с ошибкой. Исправьте калькуляцию и повторите расчёт.'
	end
end

exec tracer_log @tid, '    task_name, task_date'
	if @deal_id is not null exec deal_calc_tasks @mol_id = @mol_id, @deal_id = @deal_id, @tid = @tid

exec tracer_log @tid, '    calc RUNNING_BDS'
	update x
	set running_bds = r.value_bds
	from deals_budgets x
		join (
			select
				x.id,
				sum(value_bds) over (partition by x.deal_id order by task_date, a.name) as value_bds
			from deals_budgets x
				join #ids_deal_calc xd on xd.deal_id = x.deal_id
				join bdr_articles a on a.article_id = x.article_id								
		) r on r.id = x.id

/*
** ФОРМИРОВАНИЕ МИКРО-БЮДЖЕТОВ (ПО ТОВАРНОЙ ПОЗИЦИИ)
*/
exec tracer_log @tid, '    calc DEALS_BUDGETS_PRODUCTS'
	exec deal_calc;3 @deal_id = @deal_id, @ids = @ids

	update deals
	set update_mol_id = @mol_id,
		update_date = getdate()
	where deal_id in (select deal_id from #ids_deal_calc)

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION	
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH

	if @local_tid is not null
	begin
		exec tracer_close @local_tid
		if @trace = 1 exec tracer_view @local_tid
	end

	if object_id('tempdb.dbo.#ids_deal_calc') is not null drop table #ids_deal_calc	
	if object_id('tempdb.dbo.#b_sum') is not null drop table #b_sum
	if object_id('tempdb.dbo.#bad_costs') is not null drop table #bad_costs
	return

mbr:
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	RAISERROR('MANUAL BREAK', 16, 1)
end
go
-- helper: формирование разделов бюджета
create proc deal_calc;2
	@deal_id int,
	@tid int
as
begin

-- @projects_tasks_budgets
	declare @projects_tasks_budgets table(
		task_id int index ix_task,
		task_name varchar(250),
		date_lag int,
		article_id int index ix_article
		)

		insert into @projects_tasks_budgets(task_id, task_name, date_lag, article_id)
		select t2.task_id, t1.name, b.date_lag, b.article_id
		from projects_tasks t1
			join projects_tasks_budgets b on b.task_id = t1.task_id
			join projects_tasks t2 on t2.template_task_id = t1.task_id
		where t2.project_id = @deal_id
			and b.is_deleted = 0
			and t1.is_deleted = 0
			and t2.is_deleted = 0

exec tracer_log @tid, 'Бюджет: оплаты покупателей'
begin
	insert into deals_budgets(deal_id, type_id, task_id, task_name, article_id)
	select @deal_id, 
		1, -- оплаты покупателей
		task_id, task_name, article_id
	from @projects_tasks_budgets b
	where article_id = 24 -- Поступления по основным видам деятельности
		and not exists(select 1 from deals_budgets where deal_id = @deal_id and type_id = 1 and task_id = b.task_id)

	if not exists(select 1 from deals_budgets where deal_id = @deal_id and type_id = 1 and value_bds > 0)
		update x
		set ratio = 1, value_bdr = d.value_bdr, value_nds = d.value_nds, value_bds = d.value_bds
		from deals_budgets x
			join (
			select deal_id, sum(value_bdr) value_bdr, sum(value_nds) value_nds, sum(value_bds) value_bds
			from deals_products
			group by deal_id
			) d on d.deal_id = x.deal_id
		where x.deal_id = @deal_id
			and x.task_name = 'Подписание спецификации'

	insert into deals_budgets(deal_id, task_id, task_name, article_id)
	select @deal_id, task_id, task_name, article_id
	from @projects_tasks_budgets x
	where article_id = 24
		and not exists(select 1 from deals_budgets where deal_id = @deal_id and type_id = 1 and task_id = x.task_id)

	declare @nds_ratio float
	update deals_budgets
	set @nds_ratio = (select max(nds_ratio) from deals_products where deal_id = @deal_id),
		value_bdr = value_bds / ( 1 + @nds_ratio),
		value_nds = value_bds - value_bdr,
		nds_ratio = @nds_ratio
	where deal_id = @deal_id
		and type_id = 1
end

exec tracer_log @tid, 'Бюджет: калькуляция (суммарно)'
begin
	delete from deals_budgets where deal_id = @deal_id and type_id = 2

	insert into deals_budgets(deal_id, type_id, task_id, article_id, nds_ratio, value_bdr, value_nds, value_bds, is_automap)
	select c.deal_id, 
		2, -- работы и материалы
		0,
		c.article_id,
		0.2,
		sum(value_bdr), sum(value_nds), sum(value_bds),
		min(cast(c.is_automap as int))
	from deals_costs c
	where deal_id = @deal_id
	group by c.deal_id, c.article_id
end

exec tracer_log @tid, 'Бюджет: дополнительные расходы'
begin

	declare @NODE_EXPANSES_NAME varchar(50) = 'Дополнительные расходы';

	delete from deals_budgets where deal_id = @deal_id and type_id = 3
		and isnull(value_bdr,0) = 0

	declare @tasks_expanses table(task_id int);
	declare @node_expanses hierarchyid = (select top 1 node from projects_tasks where project_id = @deal_id and name = @NODE_EXPANSES_NAME);
		insert into @tasks_expanses(task_id) 
		select task_id from projects_tasks
		where project_id = @deal_id 
			and node.IsDescendantOf(@node_expanses) = 1

	-- append
	insert into deals_budgets(deal_id, type_id, task_id, article_id, nds_ratio)
	select @deal_id, 
		3, -- дополнительные расходы
		0,
		article_id,
		0.2
	from @projects_tasks_budgets b
	where task_id in (select task_id from @tasks_expanses)
		and not exists(select 1 from deals_budgets where deal_id = @deal_id and type_id = 3 and article_id = b.article_id)

end

exec tracer_log @tid, 'Бюджет: привязка к ИСР'
	update x
	set task_id = tb.task_id,
		date_lag = isnull(tb.date_lag,0)
	from deals_budgets x
		join bdr_articles a on a.article_id = x.article_id
			join (
				select 
					name2 = isnull(a.short_name, a.name),
					task_id = max(task_id),
					date_lag = max(date_lag)
				from @projects_tasks_budgets xx
					join bdr_articles a on a.article_id = xx.article_id
				group by isnull(a.short_name, a.name)
			) tb on tb.name2 = isnull(a.short_name, a.name)
	where x.deal_id = @deal_id
		and x.type_id not in (1)

end
go
-- helper: формирование DEALS_BUDGETS_PRODUCTS
create proc deal_calc;3
	@deal_id int = null,
	@ids app_pkids readonly,
	@serialize bit = 1
as
begin

	set nocount on;

	create table #ids_deal_calc3(deal_id int primary key)

	if @deal_id is not null insert into #ids_deal_calc3 values(@deal_id)
	else insert into #ids_deal_calc3 select id from @ids

	declare @products table(
		deal_id int index ix_deal,
		deal_product_id int,
		ratio1 float,
		ratio2 float,
		ratio3 float
		)

	insert into @products(deal_id, deal_product_id, ratio1, ratio2, ratio3)
	select x.deal_id, x.row_id
		-- коэф. для распределения поступлений
		, cast(x.value_bds  as float)
			/ nullif((select sum(value_bds) from deals_products where deal_id = xd.deal_id), 0)
		-- коэф. для распределения затрат
		, cast(x.quantity * (x.price_pure - x.price_transfer_pure)  as float)
			/ nullif((select sum(quantity * (price_pure - price_transfer_pure)) from deals_products where deal_id = xd.deal_id), 0)
		-- коэф. для распределения возмещения скидки
		, cast((
			select sum(value_bds) from deals_costs where deal_id = x.deal_id 
				and deal_product_id = x.row_id
				and article_id in (select article_id from bdr_articles where short_name = 'операционная прибыль')
		  ) as float) /
		  nullif((
			select sum(value_bds) from deals_costs where deal_id = x.deal_id 
				and article_id in (select article_id from bdr_articles where short_name = 'операционная прибыль')
			), 0)
	from deals_products x
		join #ids_deal_calc3 xd on xd.deal_id = x.deal_id

	create table #deals_budgets_products (
		deal_id int not null,
		deal_product_id int not null,
		task_id int not null,	
		task_name varchar(100),
		task_date datetime,
		date_lag int not null default 0,
		type_id int,
		article_id int not null,
		nds_ratio float default 0.18,
		ratio float,
		value_bdr float,
		value_nds float,
		value_bds float,
		)

	-- копируем калькуляцию
	insert into #deals_budgets_products(
		deal_id, deal_product_id, task_id, task_name, task_date, type_id, article_id,
		nds_ratio, value_bdr, value_nds, value_bds
		)
	select
		x.deal_id, x.deal_product_id, isnull(x.task_id,0), isnull(pt.name,'-'), pt.d_to,
		2,
		x.article_id,
		x.nds_ratio, -x.value_bdr, -x.value_nds, -x.value_bds
	from deals_costs x
		join #ids_deal_calc3 xd on xd.deal_id = x.deal_id
		left join projects_tasks pt on pt.task_id = x.task_id

	-- распределяем общие затраты
	insert into #deals_budgets_products(
		deal_id, deal_product_id, task_id, task_name, task_date, date_lag, type_id, article_id,
		nds_ratio, value_bdr, value_nds, value_bds
		)
	select
		x.deal_id, p.deal_product_id, x.task_id, x.task_name, x.task_date, x.date_lag, x.type_id, x.article_id,
		x.nds_ratio,
		p.ratio * x.value_bdr,
		p.ratio * x.value_nds,
		p.ratio * x.value_bds
	from deals_budgets x
		join (
			select 
				x.id,
				p.deal_product_id,
				case 					
					when isnull(a.short_name,'') = 'возмещение скидки' then p.ratio3
					when x.article_id = 24 then p.ratio1
					else p.ratio2
				end as ratio
			from deals_budgets x
				join @products p on p.deal_id = x.deal_id
				join bdr_articles a on a.article_id = x.article_id
		) p on p.id = x.id
	where x.deal_id in (select deal_id from #ids_deal_calc3)
		and not exists(select 1 from deals_costs where deal_id = x.deal_id and article_id = x.article_id)		

	delete from #deals_budgets_products where value_bdr is null and value_nds is null and value_bds is null

	if @serialize = 1 begin
		delete from deals_budgets_products where deal_id in (select deal_id from #ids_deal_calc3)

		insert into deals_budgets_products(
			deal_id, deal_product_id, task_id, task_name, task_date, date_lag, type_id, article_id,
			nds_ratio, value_bdr, value_nds, value_bds
			)
		select
			deal_id, deal_product_id, task_id, task_name, task_date, date_lag, type_id, article_id,
			nds_ratio, value_bdr, value_nds, value_bds
		from #deals_budgets_products		
	end

	else
		select * from #deals_budgets_products

	drop table #deals_budgets_products
end
go
