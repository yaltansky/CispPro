if object_id('deals_calc_funding') is not null drop proc deals_calc_funding
go
-- exec deals_calc_funding 1000
create proc deals_calc_funding
	@mol_id int,
	@folder_id int = null,
	@principal_id int = 9
as
begin

	set nocount on;

	create table #result(
        deal_id int primary key,
		budget_id int index ix_budget,
        value_bds float,		-- контракт
        value_paid float,		-- приход
        value_tranzit float,	-- перечислено
		value_transfer float,	-- трансферт
        value_exp1 float,		-- аг.вознагр
        value_exp2 float,		-- бм
		value_exp3 float,		-- доп.вознагр
        value_exp4 float,		-- прочие
		value_exp5 float,		-- логистика
		value_exp6 float,		-- доп.вознагр(м)
        value_exp_noinc_1 float,
        value_exp_noinc_2 float,
        value_exp_noinc_3 float,
		value_exp_noinc_31 float,		-- доп.вознагр1
		value_exp_noinc_32 float,		-- доп.вознагр2 (резерв)
		)

	-- ids
		declare @ids as app_pkids;
		
		if @folder_id is null
			insert into @ids select deal_id from deals d
				join deals_statuses ds on ds.status_id = d.status_id
			where ds.is_current = 1
		else begin
			if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
			insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'
		end

	-- deals
		insert into #result(
			deal_id, budget_id, value_bds, value_transfer
			)
		select 
			d.deal_id,
			d.budget_id,
			d.value_ccy,
			dp.value_transfer
		from deals d
			join (
				select deal_id, sum(value_transfer) as value_transfer
				from deals_products
				group by deal_id
			) dp on dp.deal_id = d.deal_id 
			join @ids i on i.id = d.deal_id		

	-- VALUE_PAID
		update x
		set value_paid = f.value_rur
		from #result x
			join (
				select budget_id, sum(value_rur) as value_rur
				from findocs#
				where article_id = 24
				group by budget_id
			) f on f.budget_id = x.budget_id

	-- VALUE_TRANZIT
		declare @principal_pred_id int = (select pred_id from subjects where subject_id = @principal_id and pred_id is not null)

		update x
		set value_tranzit = abs(f.value_rur)
		from #result x
			join (
				select budget_id, sum(value_rur) as value_rur
				from findocs#
				where value_rur < 0		
					and agent_id = @principal_pred_id
				group by budget_id
			) f on f.budget_id = x.budget_id

	-- include refund
		update x
		set value_exp1 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where db.type_id = 3
					and a.name like '%Транспорт%'
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp2 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where db.type_id = 3
					and a.name like 'Коммерческие%'
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp3 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where db.type_id = 3
					and a.name like '%Упаковка%'
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp4 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where db.type_id = 3
					and not (
						a.name like 'Коммерческие%'
						or a.name like '%Транспорт%'
						or a.name like '%Упаковка%'
						or a.name like 'Обслуживание % по финансированию%'
						)
				group by deal_id
			) b on b.deal_id = x.deal_id

	-- no refund
		update x
		set value_exp_noinc_1 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Агентское вознаграждение' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp_noinc_2 = abs(b.value_exp2)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp2
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Маркетинг' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp_noinc_31 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Дополнительное вознаграждение' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp_noinc_32 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Доп вознаграждение резерв' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update #result set value_exp_noinc_3 = isnull(value_exp_noinc_31,0) + isnull(value_exp_noinc_32,0)

	-- exp5, exp6
		update x
		set value_exp5 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Логистика' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp6 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Дополнительное вознаграждение (м)' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

	-- base
		insert into deals_funding(
			deal_id, budget_id, 
			layer,
			value_bds,
			calc_mol_id
			)
		select
			deal_id, budget_id, 
			'base',
			value_bds,
			@mol_id
		from #result r
		where not exists(select 1 from deals_funding where deal_id = r.deal_id and layer = 'base')

		update x set
			value_paid = r.value_paid,
			value_tranzit = r.value_tranzit,
			value_transfer = r.value_transfer
		from deals_funding x
			join #result r on r.deal_id = x.deal_id
		where x.layer = 'base'
		
	-- paid
		insert into deals_funding(
			deal_id, budget_id, 
			layer,
			value_exp1, value_exp2, value_exp4, value_exp5, value_exp6,
			value_exp_noinc_1, value_exp_noinc_2,
			calc_mol_id
			)
		select
			deal_id, budget_id, 
			'paid',
			value_exp1, value_exp2, value_exp4, value_exp5, value_exp6,
			value_exp_noinc_1, value_exp_noinc_2,
			@mol_id
		from #result r
		where exists(select 1 from deals_funding where deal_id = r.deal_id and layer = 'base' and value_bds = value_paid)
			and not exists(select 1 from deals_funding where deal_id = r.deal_id and layer = 'paid')

	-- shipped
		insert into deals_funding(
			deal_id, budget_id, 
			layer,
			value_exp3, value_exp_noinc_3, value_exp_noinc_31, value_exp_noinc_32,
			calc_mol_id
			)
		select
			r.deal_id, r.budget_id,
			'shipped',
			value_exp3, value_exp_noinc_3, value_exp_noinc_31, value_exp_noinc_32,
			@mol_id
		from #result r
			join deals d on d.deal_id = r.deal_id
		where d.status_id in (
				27, -- Дебиторка
				35 	-- Исполнен
				)
			and not exists(select 1 from deals_funding where deal_id = r.deal_id and layer = 'shipped')

	-- final
		drop table #result
end
go
