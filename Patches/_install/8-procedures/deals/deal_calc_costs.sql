if object_id('deal_calc_costs') is not null drop procedure deal_calc_costs
go
create proc deal_calc_costs
	@mol_id int,
	@deal_id int
as
begin
	
	set nocount on;

-- defaults
	declare @FINAL_NAME varchar(50) = 'Окончательный расчет';
	declare @NODE_COSTS_NAMES table(task_name varchar(50))
		insert into @NODE_COSTS_NAMES values
			('Финансирование материалов и работ'),
			('Финансирование материалов и кооперации'),
			(@FINAL_NAME)
	declare @NODE_EXPANSES_NAME varchar(50) = 'Дополнительные расходы';

-- #projects_tasks_budgets
	create table #projects_tasks_budgets(article_id int primary key)
		insert into #projects_tasks_budgets
		select distinct b.article_id
		from projects_tasks t1
			join projects_tasks_budgets b on b.task_id = t1.task_id
			join projects_tasks t2 on t2.template_task_id = t1.task_id
		where t2.project_id = @deal_id
			and t2.name in (select task_name from @node_costs_names)
			and b.is_deleted = 0
			and t1.is_deleted = 0
			and t2.is_deleted = 0

-- @costs
	declare @costs table(article_id int primary key, short_name varchar(50), article_ratio float, is_automap bit default(1))
		insert into @costs(article_id, short_name)
		select b.article_id, isnull(a.short_name, a.name)
		from #projects_tasks_budgets b
			join bdr_articles a on a.article_id = b.article_id

	declare @vendor_id int = (select vendor_id from deals where deal_id = @deal_id)

	if @vendor_id = 15340
-- Специальный расчёт для ВЭМЗ
	begin
		delete from deals_costs where deal_id = @deal_id
		delete from @costs
		
		declare @deal_date datetime = (select d_doc from deals where deal_id = @deal_id)

		insert into @costs(article_id, short_name, article_ratio, is_automap)
		select a.article_id, a.short_name, aa.article_ratio / 100,  0
		from bdr_articles a
			join deals_costs_koefs aa on 
					aa.slice = case 
							when @deal_date < '2019-11-01' then 'base'
							when @deal_date < '2020-07-01' then '201911'
							when @deal_date < '2021-06-01' then '202007'
							else '202105'
						end
				and aa.short_name = a.short_name 
				and (aa.subject_id is null or aa.subject_id = a.subject_id)
	end

	else begin
		update @costs
		set article_ratio = 
				case
					when short_name = 'Агентское вознаграждение' then 0.033
					when short_name = 'Маркетинг' then 0.007
					else article_ratio
				end
	end


	declare @nds decimal(8,2) = dbo.get_nds()

-- Формируем калькуляцию
	declare @deals_costs table(
		row_id int identity primary key,
		deal_id int,
		deal_product_id int,
		deal_product_name varchar(250), article_id int, nds_ratio float,
		value_bdr float, value_nds float, value_bds float,
		is_automap bit,
		index ix_deal_product(deal_id, deal_product_id)
	)
	insert into @deals_costs(deal_id, deal_product_id, deal_product_name, article_id, nds_ratio, value_bdr, value_nds, value_bds, is_automap)
	select @deal_id, x.row_id, x.name, x.article_id, @nds,
		x.value_bdr,
		x.value_bdr * @nds,
		x.value_bdr + cast(x.value_bdr * @nds as float),
		x.is_automap
	from (
		select d.row_id, d.name, c.article_id,
			d.price_transfer_pure * d.quantity * c.article_ratio as 'value_bdr',
			c.is_automap
		from deals_products d, @costs c
		where d.deal_id = @deal_id
		) x

-- Учёт точности округления
	declare @deals_costs_diff table(cost_row_id int, deal_product_id int, diff float)
		insert into @deals_costs_diff(cost_row_id, deal_product_id, diff)
		select c.cost_row_id, p.row_id
			, cost_transfer_pure_diff = (p.price_transfer_pure * p.quantity) - c.cost_pure
		from deals_products p
			join (
				select deal_id, deal_product_id, max(row_id) as cost_row_id, sum(value_bdr) as cost_pure
				from @deals_costs
				group by deal_id, deal_product_id
			) c on c.deal_id = p.deal_id and c.deal_product_id = p.row_id
	
	if (select max(abs(diff)) from @deals_costs_diff) < 1.00
	begin
		update x
		set value_bdr = x.value_bdr + xx.diff
		from @deals_costs x
			join @deals_costs_diff xx on xx.cost_row_id = x.row_id
	end

-- Сохраняем данные
	insert into deals_costs(deal_id, deal_product_id, deal_product_name, article_id, nds_ratio, value_bdr, value_nds, value_bds, is_automap)
	select 
		x.deal_id, x.deal_product_id, x.deal_product_name, x.article_id,
		x.nds_ratio, x.value_bdr, x.value_nds, x.value_bds,
		x.is_automap
	from @deals_costs x
		join bdr_articles a on a.article_id = x.article_id
	where not exists(
		select 1 from deals_costs dc 
			join bdr_articles aa on aa.article_id = dc.article_id
		where deal_id = @deal_id 
			and deal_product_id = x.deal_product_id
			and isnull(aa.short_name, aa.name) = isnull(a.short_name, a.name)
		)

end
go
