if object_id('deals_reps_funding') is not null drop proc deals_reps_funding
go
-- exec deals_reps_funding 1000, 14412
create proc deals_reps_funding
	@mol_id int,
	@folder_id int,
	@trace bit = 0
as
begin

	set nocount on;

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id

	create table #resultFunds(
		row_id int identity primary key,
		--
		budget_id int index ix_budget,
		article_id int index ix_article,
        --
		p1_payorder_id int,
		p1_date datetime,
		p1_number varchar(500),
		p1_value float,
        --
		p2_payorder_id int,
        p2_date datetime,
		p2_number varchar(500),
        p2_value float,
        --
		value float,
		slice varchar(100),
        note varchar(max)
		)

	exec deals_reps_funding;2 
		@mol_id = @mol_id,
		@folder_id = @folder_id,
		@ids = @ids,
		@objects = @objects,
		@trace = @trace

-- result
	select
		subject_name = s.short_name,
		d.vendor_name,
		d.direction_name,
		d.mol_name,
		d.agent_name,
		number = d.number,
		article_name = a.name,
		x.p1_date,
		p1_number = isnull(x.p1_number, ''),
		x.p2_date,
		p2_number = isnull(x.p2_number, ''),
		x.slice,
		x.note,
		x.p1_value,
		x.p2_value,
        d.deal_hid,
		d.budget_hid,
		p1_payorder_hid = concat('#', x.p1_payorder_id),
		p2_payorder_hid = concat('#', x.p2_payorder_id),
		article_hid = concat('#', a.article_id)
	from #resultFunds x
		join v_deals d on d.budget_id = x.budget_id
			left join subjects s on s.subject_id = d.subject_id
		left join bdr_articles a on a.article_id = x.article_id

	drop table #resultFunds
end
GO
create proc deals_reps_funding;2
	@mol_id int,
	@folder_id int,
	@ids app_pkids readonly,
	@objects app_objects readonly,
	@skip_access bit = 0,
	@trace bit = 0
as
begin

	DECLARE @CHECK_F1_VALUE MONEY, @CHECK_F2_VALUE MONEY

	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @vendors as app_pkids; insert into @vendors select distinct obj_id from @objects where obj_type = 'vnd'
	declare @budgets_allowed as app_pkids; insert into @budgets_allowed select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit = case when exists(select 1 from @budgets_allowed where id = -1) then 1 else 0 end

	declare @budgets as app_pkids
	insert into @budgets
	select budget_id
	from deals d
		join @ids i on i.id = d.deal_id		
	where (
		@skip_access = 1
		or d.subject_id in (select id from @subjects)
		or d.vendor_id in (select id from @vendors)
		or (@all_budgets = 1 or d.budget_id in (select id from @budgets_allowed))
		)

begin

	select top 0 * into #require from #resultFunds
		create unique clustered index pk_require on #require(row_id)
		create index ix_require_budget on #require(budget_id)
		create index ix_require_budgetarticle on #require(budget_id, article_id)
	
	select top 0 * into #provide from #resultFunds
		create unique clustered index pk_provide on #provide(row_id)
		create index ix_provide_budget on #provide(budget_id)
		create index ix_provide_budgetarticle on #provide(budget_id, article_id)

	declare @fid uniqueidentifier set @fid = newid()

end -- tables

/*
** Потоки:
	(F1) Выдача кредита
	(F2) Погашение кредита
*/

-- MIX1 = FIFO(F1,F2)
begin

	insert into #require(budget_id, article_id, p1_payorder_id, p1_date, p1_number, value)
	select x.budget_id, x.article_id, o.payorder_id, o.d_add, 
        substring(concat(o.number, ':', x.note), 1, 500),
        abs(x.value_rur)
	from payorders_details x
		join payorders o on o.payorder_id = x.payorder_id
		join @budgets i on i.id = x.budget_id
		join bdr_articles a on a.article_id = x.article_id
			left join deals_articles_priority ap on ap.article_short_name = isnull(a.short_name, a.name)
	where o.type_id = 2
		and o.status_id >= 0
		and x.is_deleted = 0
	order by x.budget_id, isnull(ap.sort_std, 9999), o.d_add

	insert into #provide(budget_id, article_id, p2_payorder_id, p2_date, p2_number, value)
	select x.budget_id, x.article_id, o.payorder_id, o.d_add, 
		substring(concat(o.number, ':', x.note), 1, 500),
		abs(x.value_rur)
	from payorders_details x
		join payorders o on o.payorder_id = x.payorder_id
		join @budgets i on i.id = x.budget_id
		join bdr_articles a on a.article_id = x.article_id
			left join deals_articles_priority ap on ap.article_short_name = isnull(a.short_name, a.name)
	where o.type_id = 3
		and o.status_id >= 0
		and x.is_deleted = 0
	order by x.budget_id, isnull(ap.sort_std, 9999), o.d_add

	insert into #resultFunds(
		budget_id, article_id, p1_payorder_id, p1_date, p1_number, p2_payorder_id, p2_date, p2_number, p1_value, p2_value, slice, note
		)
	select 
		r.budget_id, p.article_id,
		r.p1_payorder_id, r.p1_date, r.p1_number,
		p.p2_payorder_id, p.p2_date, p.p2_number,
		f.value, f.value,
		'MIX1', 'FIFO(F1,F2)'
	from #require r
		join #provide p on p.budget_id = r.budget_id and p.article_id = r.article_id
		cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
	order by r.row_id, p.row_id

	-- left (F1 без F2)
	insert into #resultFunds(budget_id, article_id, p1_payorder_id, p1_date, p1_number, p1_value, slice, note)
	select 
		x.budget_id, x.article_id,
		x.p1_payorder_id, x.p1_date, x.p1_number,
		f.value,
		'MIX1.left', 'F1 без F2'
	from dbo.fifo_left(@fid) f
		join #require x on x.row_id = f.row_id
	where f.value >= 0.01
	
	-- left (F1 без F2 (2))
	insert into #resultFunds(budget_id, article_id, p1_payorder_id, p1_date, p1_number, p1_value, slice, note)
	select 
		x.budget_id, x.article_id, x.p1_payorder_id, x.p1_date, x.p1_number, x.value,
		'MIX1.left2', 'F1 без F2 (2)'
	from #require x
	where not exists(select 1 from #provide where budget_id = x.budget_id and article_id = x.article_id)

	-- right (F2 без F1)
	insert into #resultFunds(budget_id, article_id, p2_payorder_id, p2_date, p2_number, p2_value, slice, note)
	select 
		x.budget_id, x.article_id, x.p2_payorder_id, x.p2_date, x.p2_number,
		f.value,	
		'MIX1.right', 'F2 без F1'
	from dbo.fifo_right(@fid) f
		join #provide x on x.row_id = f.row_id
	where f.value >= 0.01

	-- right (F2 без F1 (2))
	insert into #resultFunds(budget_id, article_id, p2_payorder_id, p2_date, p2_number, p2_value, slice, note)
	select 
		x.budget_id, x.article_id, x.p2_payorder_id, x.p2_date, x.p2_number, x.value,
		'MIX1.right2', 'F2 без F1 (2)'
	from #provide x
	where not exists(select 1 from #require where budget_id = x.budget_id and article_id = x.article_id)

	IF @TRACE = 1 BEGIN
		SELECT @CHECK_F1_VALUE = (SELECT SUM(VALUE) FROM #REQUIRE)
		SELECT @CHECK_F2_VALUE = (SELECT SUM(VALUE) FROM #PROVIDE)
	END
end -- MIX1 = FIFO(F1,F2)

IF @TRACE = 1 BEGIN
	SELECT 
		CHECK_F1_VALUE = cast(@CHECK_F1_VALUE - SUM(P1_VALUE) as money),
		CHECK_F2_VALUE = cast(@CHECK_F2_VALUE - SUM(P2_VALUE) as money)
	FROM #resultFunds
END

-- clear temp
	exec fifo_clear @fid
	drop table #require, #provide

end
