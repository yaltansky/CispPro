if object_id('findoc_bindfolder') is not null drop proc findoc_bindfolder
go
create proc [findoc_bindfolder]
	@mol_id int,
	@findoc_id int,
	@folder_id int
as
begin

	set nocount on;

	declare @d_from datetime

	select 
		@d_from = d_doc
	from objs_folders
	where folder_id = @folder_id

	create table #deals (
		row_id int identity,
		folder_id int,
		budget_id int,
		value_start decimal(18,2),
		value_in decimal(18,2),
		value_held decimal(18,2),
		value_undefined decimal(18,2),
		value_out_calc decimal(18,2),
		value_out decimal(18,2),
		constraint pk_deals primary key (folder_id, budget_id)
		)
		create unique index ix_deals on #deals(row_id)

	create table #budgets (
		row_id int identity,
		folder_id int,
		budget_id int,
		article_id int,
		value_plan decimal(18,2),
		value_fact decimal(18,2),
		constraint pk_budgets primary key (folder_id, budget_id, article_id)
		)
		create unique index ix_budgets on #budgets(row_id)

-- #findocs
	insert into #deals(folder_id, budget_id, value_in, value_out)
	select 
		fd.folder_id,
		f.budget_id,
		sum(case when f.value_ccy > 0 then f.value_ccy else 0 end),
		sum(case when f.value_ccy < 0 then f.value_ccy else 0 end)
	from v_findocs f
		join objs_folders_details fd on fd.obj_id = f.findoc_id and fd.obj_type = 'fd'
	where fd.folder_id = @folder_id
	group by fd.folder_id, f.budget_id

	update x
	set value_start = isnull(xx.value_ccy,0)
	from #deals x
		join (
			select budget_id, sum(value_ccy) as value_ccy
			from v_findocs
			where d_doc < @d_from
			group by budget_id
		) xx on xx.budget_id = x.budget_id

	-- value_start
	update x
	set value_start = isnull(xx.value_ccy,0)
	from #deals x
		join (
			select budget_id, sum(value_ccy) as value_ccy
			from v_findocs
			where d_doc < @d_from
			group by budget_id
		) xx on xx.budget_id = x.budget_id

	-- value_undefined 
	update #deals
	set value_undefined = value_in,
		value_in = 0
	where budget_id = 0
		and value_in > 0

	-- value_held
	update #deals
	set value_held = case when value_start > 0 then value_in - value_start else 0 end
	where budget_id <> 0

	-- value_out_calc
	update #deals
	set value_out_calc = value_in - value_held
	where budget_id <> 0

-- перечислить
	-- select * from #deals where value_out_calc > 0

-- расчёт бюджетов
	insert into #budgets(folder_id, budget_id, article_id, value_plan, value_fact)
	select @folder_id, budget_id, article_id, sum(value_plan), sum(value_fact)
	from (
		select b.budget_id, x.article_id, x.value_bds as value_plan, cast(0 as decimal(18,2)) as value_fact
		from deals_budgets x
			join deals d on d.deal_id = x.deal_id
				join budgets b on b.project_id = d.deal_id
		where b.budget_id in (select budget_id from #deals)
		
		union all
		select budget_id, article_id, 0, sum(value_ccy)
		from v_findocs
		where d_doc < @d_from
			and budget_id in (select budget_id from #deals)
		group by budget_id, article_id
		) u
	group by budget_id, article_id

-- база распределения ФИФО
	create table #require(
		row_id int identity primary key,
		budget_id int,
		article_id int,
		value float
		)

	insert into #require(budget_id, article_id, value)
	select budget_id, article_id, -(value_plan - value_fact)
	from #budgets 
	where budget_id not in (0,33)
		and value_plan < 0
		and value_plan - value_fact < 0
	order by budget_id, article_id
	   
	declare @uid uniqueidentifier set @uid = newid()
	exec fifo_clear @uid

	create table #provide(row_id int identity, value float)
	insert into #provide(value) 
	select -value_ccy from findocs where findoc_id = @findoc_id
		and value_ccy < 0 -- только расходы (инверсия знака для ФИФО)

-- FINAL: детализация оплаты
BEGIN TRY
BEGIN TRANSACTION

	delete from findocs_details where findoc_id = @findoc_id
	
	insert into findocs_details(findoc_id, budget_id, article_id, value_ccy)
	select
		@findoc_id,
		r.budget_id,
		r.article_id,
		-f.value
	from #require r
		join #provide p on p.value > 0
		cross apply dbo.fifo(@uid, p.row_id, p.value, r.row_id, r.value) f

	if not exists(select 1 from objs_folders_details where folder_id = @folder_id and obj_type = 'fd' and obj_id = @findoc_id)
	begin
		insert into objs_folders_details(folder_id, obj_id, obj_type, add_mol_id)
		values (@folder_id, @findoc_id, 'fd', @mol_id)
	end

COMMIT TRANSACTION
END TRY

BEGIN CATCH

	declare @err varchar(max) set @err = error_message()
	raiserror (@err, 16, 1)
		
ROLLBACK TRANSACTION
END CATCH

	drop table #deals, #budgets, #require, #provide

end
GO
