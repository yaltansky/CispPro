if object_id('deals_reps_paysfifo') is not null drop proc deals_reps_paysfifo
go
-- exec deals_reps_paysfifo 700, 12419
create proc deals_reps_paysfifo
	@mol_id int,
	@folder_id int,
	@trace bit = 0
as
begin

	set nocount on;

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id

	create table #resultDealsPaysFifo(
		row_id int identity primary key,
		--
		deal_id int index ix_deal,
        --
		b_date datetime,
		b_step varchar(100),
        b_article_id int, -- статья
		b_value decimal(18,2),
        --
        p_date datetime, -- плановая дата (по условию оплаты)
		p_step varchar(100), -- условие оплаты
		p_article_id int,
        p_value decimal(18,2),
        --
        f_date datetime,        
		f_number varchar(100),
		f_value decimal(18,2),
        --
		value decimal(18,2),		
		slice varchar(100),
        note varchar(max),
        --
        findoc_id int index ix_findoc
		)

	exec deals_reps_paysfifo;2
		@mol_id = @mol_id,
		@ids = @ids,
		@objects = @objects,
		@trace = @trace

-- result
	select
		subject_name = s.short_name,
		d.vendor_name,
		d.direction_name,
		d.mol_name,
		d.deal_name,
		x.b_date,
		x.b_step,
		b_article_name = a.name,
		x.p_date,
		x.p_step,
		p_article_name = a2.name,
		f_number = isnull(x.f_number, ''),
		x.f_date,
		x.slice,
		x.note,
		x.b_value,
		x.p_value,
        x.f_value,
        d.deal_hid,
		d.budget_hid,
		article_hid = concat('#', a.article_id),
		findoc_hid = concat('#', x.findoc_id)
	from #resultDealsPaysFifo x
		join v_deals d on d.deal_id = x.deal_id
			join subjects s on s.subject_id = d.subject_id
		left join bdr_articles a on a.article_id = x.b_article_id
		left join bdr_articles a2 on a2.article_id = x.p_article_id

    drop table #resultDealsPaysFifo

end
GO

create proc deals_reps_paysfifo;2
	@mol_id int,
	@principal_id int = null,
	@ids app_pkids readonly,
	@objects app_objects readonly,
	@skip_access bit = 0,
	@trace bit = 0
as
begin

	DECLARE @CHECK_B_VALUE MONEY, @CHECK_P_VALUE MONEY, @CHECK_F_VALUE MONEY

	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit = case when exists(select 1 from @budgets where id = -1) then 1 else 0 end

	if @all_budgets = 0 and @skip_access = 0
	begin
		raiserror('Для просмотра данного отчёта должен быть доступ ко всем бюджетам. Формирование отчёта приостановлено.', 16, 1)
		return
	end

begin

	select top 0 * into #req from #resultDealsPaysFifo
		create unique clustered index pk_require on #req(row_id)
	
	select top 0 * into #prv from #resultDealsPaysFifo
		create unique clustered index pk_provide on #prv(row_id)

	declare @fid uniqueidentifier set @fid = newid()

end -- tables

-- MIX1 = FIFO(Бюджет, Плановые поступления)

begin

	insert into #req(deal_id, b_date, b_step, b_article_id, value)
	select deal_id, task_date, task_name, article_id, value_bds
	from (
		select 
			db.deal_id, db.task_date, db.task_name, db.article_id, 
			isnull(
				case when d.nds_ratio = 0 then ap.sort_nds0 else ap.sort_std end,
				9999) as sort_id,
			value_bds = -db.value_bds
		from deals_budgets db
			join deals d on d.deal_id = db.deal_id
			join @ids i on i.id = db.deal_id
			join bdr_articles a on a.article_id = db.article_id
				left join deals_articles_priority ap on ap.article_short_name = isnull(a.short_name, a.name)
		where db.value_bds < 0 -- затраты
		) x
	order by deal_id, task_date, sort_id, task_name

	insert into #prv(deal_id, p_date, p_step, p_article_id, value)
	select deal_id, task_date, 
		 concat(
			row_number() over (partition by x.deal_id order by x.task_date, x.task_name), '-',		
			dbo.deal_paystepname(x.task_name, x.date_lag, x.ratio)
			)
		, x.article_id, value_bds
	from deals_budgets x
		join @ids i on i.id = x.deal_id
	where x.value_bds > 0 -- оплаты
	order by deal_id, task_date, task_name

	insert into #resultDealsPaysFifo(
		deal_id, b_date, b_step, b_article_id, p_date, p_step, p_article_id, b_value, p_value, slice, note
		)
	select r.deal_id,
		r.b_date, r.b_step, r.b_article_id,
		p.p_date, p.p_step, p.p_article_id,
		f.value, f.value,
		'MIX1', 'FIFO(Бюджет, Плановые поступления)'
	from #req r
		join #prv p on p.deal_id = r.deal_id
		cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
	order by r.row_id, p.row_id

	-- left (бюджет без плановых поступлений)
	insert into #resultDealsPaysFifo(deal_id, b_step, b_date, b_article_id, b_value, slice, note)
	select 
		x.deal_id, x.b_step, x.b_date, x.b_article_id,
		f.value,
		'MIX1.left', 'бюджет без плановых поступлений'
	from dbo.fifo_left(@fid) f
		join #req x on x.row_id = f.row_id
	where f.value >= 0.01
	
	-- left (бюджет без плановых поступлений (2))
	insert into #resultDealsPaysFifo(deal_id, b_step, b_date, b_article_id, b_value, slice, note)
	select 
		x.deal_id, x.b_step, x.b_date, x.b_article_id, x.value,
		'MIX1.left2', 'бюджет без плановых поступлений(2)'
	from #req x
	where not exists(select 1 from #prv where deal_id = x.deal_id)

	-- right (плановые поступления без бюджета)
	insert into #resultDealsPaysFifo(deal_id, p_date, p_step, p_article_id, p_value, slice, note)
	select 
		x.deal_id, x.p_date, x.p_step, x.p_article_id,
		f.value,	
		'MIX1.right', 'плановые поступления без бюджета'
	from dbo.fifo_right(@fid) f
		join #prv x on x.row_id = f.row_id
	where f.value >= 0.01

	-- right (плановые поступления без бюджета(2))
	insert into #resultDealsPaysFifo(deal_id, p_date, p_step, p_article_id, p_value, slice, note)
	select 
		x.deal_id, x.p_date, x.p_step, x.p_article_id, x.value,
		'MIX1.right2', 'бюджет без плановых поступлений(2)'
	from #prv x
	where not exists(select 1 from #req where deal_id = x.deal_id)
	
end -- MIX1 = FIFO(Бюджет, Плановые поступления)\

IF @TRACE = 1 BEGIN
	SELECT @CHECK_B_VALUE = (SELECT SUM(VALUE) FROM #REQUIRE)
	SELECT @CHECK_P_VALUE = (SELECT SUM(VALUE) FROM #PROVIDE)
END

-- MIX2 = FIFO(MIX1, Факт)
begin

	exec fifo_clear @fid;
	delete from #req
	delete from #prv

	update #resultDealsPaysFifo set slice = 'mix3' where p_value is null

	insert into #req(deal_id, b_date, b_step, b_article_id, p_date, p_step, p_article_id, b_value, value)
	select deal_id, b_date, b_step, b_article_id, p_date, p_step, p_article_id, b_value, p_value
	from #resultDealsPaysFifo
	where slice like 'mix1%'
	order by deal_id, row_id

	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

	insert into #prv(deal_id, f_date, findoc_id, f_number, value)
	select d.deal_id, x.d_doc, x.findoc_id, f.number, sum(x.value_rur)
	from findocs# x 
		join budgets b on b.budget_id = x.budget_id
			join deals d on d.budget_id = b.budget_id
				join @ids i on i.id = d.deal_id
		join findocs f on f.findoc_id = x.findoc_id
	where x.value_rur > 0
		and f.account_id not in (select account_id from findocs_accounts where name = @vat_refund)
		and (
			@principal_id is null
			or (
				f.subject_id != @principal_id
				and f.agent_id not in (select pred_id from subjects where subject_id = @principal_id)
			)
		)
	group by d.deal_id, x.d_doc, x.findoc_id, f.number
	order by d.deal_id, x.d_doc

	insert into #resultDealsPaysFifo(
		deal_id, b_date, b_step, b_article_id, p_date, p_step, p_article_id, f_date, f_number, findoc_id, b_value, p_value, f_value, slice, note
		)
	select 
		r.deal_id, r.b_date, r.b_step, r.b_article_id, r.p_date, r.p_step, r.p_article_id,
		p.f_date, p.f_number, p.findoc_id,
		--
		case when r.b_value is not null then f.value end,
		f.value, f.value,
		--
		'MIX2', 'FIFO(MIX1, Факт)'
	from #req r
		join #prv p on p.deal_id = r.deal_id
		cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
	order by r.row_id, p.row_id

	-- left (MIX1 без фактических поступлений)
	insert into #resultDealsPaysFifo(deal_id, b_date, b_step, b_article_id, p_date, p_step, p_article_id, b_value, p_value, slice, note)
	select 
		x.deal_id, x.b_date, x.b_step, x.b_article_id, x.p_date, x.p_step, x.p_article_id,
		--
		case when x.b_value is not null then f.value end,
		f.value,
		--
		'MIX2.left', 'MIX1 без факта'
	from dbo.fifo_left(@fid) f
		join #req x on x.row_id = f.row_id
	where f.value >= 0.01

	-- left (MIX1 без фактических поступлений(2))
	insert into #resultDealsPaysFifo(deal_id, b_date, b_step, b_article_id, p_date, p_step, p_article_id, b_value, p_value, slice, note)
	select 
		deal_id, b_date, b_step, b_article_id, p_date, p_step, p_article_id,
		--
		b_value, value,
		--
		'MIX2.left2', 'MIX1 без факта(2)'
	from #req x
	where not exists(select 1 from #prv where deal_id = x.deal_id)

	-- right (фактические поступления без MIX1)
	insert into #resultDealsPaysFifo(deal_id, f_date, f_number, findoc_id, f_value, slice, note)
	select 
		x.deal_id, x.f_date, x.f_number, x.findoc_id, f.value,
		'MIX2.right', 'фактические поступления без MIX1'
	from dbo.fifo_right(@fid) f
		join #prv x on x.row_id = f.row_id
	where f.value >= 0.01

	-- right (фактические поступления без MIX1(2))
	insert into #resultDealsPaysFifo(deal_id, f_date, f_number, findoc_id, f_value, slice, note)
	select 
		deal_id, f_date, f_number, findoc_id, value,
		'MIX2.right2', 'фактические поступления без MIX1(2)'
	from #prv x
	where not exists(select 1 from #req where deal_id = x.deal_id)

	delete from #resultDealsPaysFifo where slice like 'mix1%'
end -- MIX2 = FIFO(MIX1, Факт)

--select deal_id, sum(value)
--from (
--	select deal_id, value = sum(value) from #prv group by deal_id
--	union all
--	select deal_id, -sum(f_value) from #resultDealsPaysFifo group by deal_id
--	) u
--group by deal_id
--having sum(value) <> 0

IF @TRACE = 1 BEGIN
	SELECT @CHECK_F_VALUE = (SELECT SUM(VALUE) FROM #PROVIDE)

	SELECT 
		CHECK_B_VALUE = @CHECK_B_VALUE - SUM(B_VALUE),
		CHECK_P_VALUE = @CHECK_P_VALUE - SUM(P_VALUE),
		CHECK_F_VALUE = @CHECK_F_VALUE - SUM(F_VALUE)
	FROM #resultDealsPaysFifo
END

e:
-- clear temp
	exec fifo_clear @fid
	drop table #req, #prv

end
go
