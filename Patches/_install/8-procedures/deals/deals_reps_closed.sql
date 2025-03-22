if object_id('deals_reps_closed') is not null drop proc deals_reps_closed
go
-- exec deals_reps_closed 700, 8384
create proc deals_reps_closed
	@mol_id int,
	@folder_id int,
	@principal_id int = 9,
	@include_refund bit = 0	
as
begin

	set nocount on;

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @vendors as app_pkids; insert into @vendors select distinct obj_id from @objects where obj_type = 'vnd'
	-- @budgets
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit = case when exists(select 1 from @budgets where id = -1) then 1 else 0 end

	create table #result(
        DEAL_ID INT PRIMARY KEY,
		BUDGET_ID INT,
		BASE_NAME VARCHAR(250),
        MFR_NAME VARCHAR(50),
        AGENT_NAME VARCHAR(250),
		DOGOVOR_NUMBER VARCHAR(50),
        SPEC_DATE DATETIME,
		SPEC_NUMBER VARCHAR(100),
        DEAL_NUMBER VARCHAR(50),
        VER_DATE DATETIME,
        VER_NUMBER VARCHAR(30),
        VALUE_BDS FLOAT,			-- Контракт | СумКонтракт
        VALUE_PAID FLOAT,		-- Приход | СумПриход
        VALUE_TRANZIT FLOAT,		-- Перечислено | СумПеречислено
		VALUE_TRANSFER FLOAT	,	-- Трансферт | СумТрансферт
        VALUE_EXP1 FLOAT,		-- Аг.вознагр | СумТранспорт
        VALUE_EXP2 FLOAT,		-- БМ | СумМаркетинг
		VALUE_EXP3 FLOAT,		-- Доп.вознагр | СумУпаковка
		VALUE_EXP31 FLOAT,		-- Доп.вознагр1 (Доп вознаграждение)
		VALUE_EXP32 FLOAT,		-- Доп.вознагр2 (Доп вознаграждение резерв)
        VALUE_EXP4 FLOAT,		-- СумПрочие
		VALUE_EXP5 FLOAT,		-- Логистика  | RESERVED_3
		VALUE_EXP6 FLOAT			-- Доп.вознагрМ |  | RESERVED_4
		)

	declare @ids as app_pkids;
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'

	insert into #result(
		deal_id, budget_id, base_name, mfr_name, agent_name, dogovor_number, spec_date, spec_number, deal_number, ver_date, ver_number, value_bds, value_transfer
		)
	select 
		d.deal_id,
		d.budget_id,
		isnull(docs1.number, d.buh_principal_number),
		sv.short_name,
		concat(a.name, ', ИНН ', a.INN),
		d.dogovor_number,
		d.spec_date,
		d.spec_number,
		d.number,
		d.ver_date,
		d.ver_number,
		d.value_ccy,
		dp.value_transfer
	from deals d
		join (
			select deal_id, sum(value_transfer) as value_transfer
			from deals_products
			group by deal_id
		) dp on dp.deal_id = d.deal_id 
		join @ids i on i.id = d.deal_id		
		left join subjects sv on sv.subject_id = d.vendor_id
		left join agents a on a.agent_id = d.customer_id
		left join deals_docs_principals docs1 on docs1.document_id = d.buh_principal_id
	where 
		-- access
		(
		d.subject_id in (select id from @subjects)
		or d.vendor_id in (select id from @vendors)
		or (@all_budgets = 1 or d.budget_id in (select id from @budgets))
		)

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

-- VALUE_EXP1
	if @include_refund = 1
	begin
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
	end

	else
	begin

		update x
		set value_exp1 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Агентское вознаграждение' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp2 = abs(b.value_exp2)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp2
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Маркетинг' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp31 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Дополнительное вознаграждение' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update x
		set value_exp32 = abs(b.value_exp)
		from #result x
			join (
				select deal_id, sum(value_bds) as value_exp
				from deals_budgets db
					join bdr_articles a on a.article_id = db.article_id
				where a.short_name = 'Доп вознаграждение резерв' -- группа статей
				group by deal_id
			) b on b.deal_id = x.deal_id

		update #result set value_exp3 = isnull(value_exp31,0) + isnull(value_exp32,0)
	end

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

-- final
	select * from #result
	drop table #result
end
go