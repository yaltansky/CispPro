if object_id('project_buys_calc') is not null drop proc project_buys_calc
go
create proc project_buys_calc
	@project_id int
as
begin

	set nocount on;

-- hierarchyid
	declare @where_rows varchar(100) = 'project_id = ' + cast(@project_id as varchar)
	exec tree_calc_nodes 'projects_buys', 'buy_id', @where_rows = @where_rows, @sortable = 0

-- sum plan_rur
	update x
	set plan_rur = (
			select sum(plan_rur)
			from projects_buys
			where project_id = @project_id
				and node.IsDescendantOf(x.node) = 1
				and has_childs = 0
			)
	from projects_buys x
	where x.project_id = @project_id
		and x.has_childs = 1

-- fifo
	exec project_buys_calc;2 @project_id 
end
GO

create proc project_buys_calc;2
	@project_id int
as
begin

	set nocount on;

	declare @refkey varchar(50) = '/projects/' + cast(@project_id as varchar)

	create table #provide  (row_id int identity primary key, d_doc datetime, doc_id int, product_id int, value float)
	create table #require (row_id int identity primary key, d_doc datetime, doc_id int, product_id int, q_spec float, q_buy float, q_stock float, q_mfs float, q_left float, value float)
	
-- спецификации
	insert into #require(doc_id, d_doc, product_id, q_spec, value)
	select s.doc_id, s.d_doc, sp.product_id, sum(sp.quantity), sum(sp.quantity)
	from sdocs s
		join sdocs_products sp on sp.doc_id = s.doc_id
	where s.refkey = @refkey
		and s.type_id = 1
	group by s.d_doc, s.doc_id, sp.product_id

	declare @uid uniqueidentifier set @uid = newid()
		
	delete from projects_buys_sheets_details where project_id = @project_id

-- Зачёт cпецификаций документами 
	exec project_buys_calc;3 @project_id, @refkey, @uid, 4 -- "Выдача в производство"
	exec project_buys_calc;3 @project_id, @refkey, @uid, 3 -- "Склад"
	exec project_buys_calc;3 @project_id, @refkey, @uid, 2 -- "Закупки"

-- save result
	delete from projects_buys_sheets where project_id = @project_id
	
	insert into projects_buys_sheets(project_id, product_id, quantity, q_buy, q_stock, q_mfs, q_left)
	select project_id, product_id, quantity, q_buy, q_stock, q_mfs,
		isnull(q_buy, 0) + isnull(q_stock, 0) + isnull(q_mfs, 0) - isnull(quantity, 0) -- <0 - дефицит, >0 - профицит
	from (
		select project_id, product_id
			, sum(quantity) as quantity
			, sum(q_buy) as q_buy
			, sum(q_stock) as q_stock
			, sum(q_mfs) as q_mfs
		from projects_buys_sheets_details x
		where project_id = @project_id
		group by project_id, product_id
		) x
end
go

create proc project_buys_calc;3
	@project_id int,
	@refkey varchar(50),
	@uid uniqueidentifier,
	@type_id int
as
begin

	exec fifo_clear @uid
	delete from #provide;

	insert into #provide(doc_id, d_doc, product_id, value)
	select s.doc_id, s.d_doc, sp.product_id, sum(sp.quantity)
	from sdocs s
		join sdocs_products sp on sp.doc_id = s.doc_id
	where s.refkey = @refkey
		and s.type_id = @type_id
	group by s.doc_id, s.d_doc, sp.product_id

	create table #result(req_row_id int, prv_row_id int, crossed float)

	-- FIFO: Требования (#require) зачитываются Обеспечением (#provide)
	insert into #result(req_row_id, prv_row_id, crossed)
	select r.row_id, p.row_id, f.value
	from #require r
		inner join #provide p on p.product_id = r.product_id
		cross apply dbo.fifo(@uid, p.row_id, p.value, r.row_id, r.value) f
	order by r.row_id, p.row_id

	-- осталось приходов (1)
	insert into #result(prv_row_id, crossed)
	select row_id, value
	from dbo.fifo_right(@uid)
	where value > 0

	-- осталось приходов (2)
	insert into #result(prv_row_id, crossed)
	select row_id, value
	from #provide
	where row_id not in (select prv_row_id from #result)

	if @type_id = 2 -- Тип "Закупка" - это признак последней серии обеспечения.
					-- Поэтому нам надо знать, сколько осталось не обеспеченных заказов
		insert into #result(req_row_id, crossed)
		select row_id, value
		from dbo.fifo_left(@uid)
		where value > 0

	declare @sql nvarchar(max) = '
	update x
	set value = x.value - isnull(r.crossed,0),
		%q_column = r.crossed
	from #require x
		join (
			select req_row_id, sum(crossed) as crossed
			from #result
			where prv_row_id is not null
			group by req_row_id
		) r on r.req_row_id = x.row_id

	insert into projects_buys_sheets_details(project_id, product_id, out_doc_id, out_d_doc, in_doc_id, in_d_doc, quantity, %q_column)
	select %project_id, isnull(o.product_id, i.product_id), o.doc_id, o.d_doc, i.doc_id, i.d_doc, 
		case when o.doc_id is not null then r.crossed else 0 end,
		case when i.doc_id is not null then r.crossed else 0 end
	from #result r
		left join #provide i on i.row_id = r.prv_row_id
		left join #require o on o.row_id = r.req_row_id
	'

	set @sql = replace(@sql, '%q_column', 
		case @type_id
			when 2 then 'q_buy'
			when 3 then 'q_stock'
			when 4 then 'q_mfs'
		end
		)
	set @sql = replace(@sql, '%project_id', @project_id)

	exec sp_executesql @sql
end
go