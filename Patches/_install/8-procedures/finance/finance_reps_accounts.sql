if object_id('finance_reps_accounts') is not null drop proc finance_reps_accounts
go
-- exec finance_reps_accounts 1000, 9, '2022-03-01'
create proc finance_reps_accounts
	@mol_id int,
	@subject_id int,
	@d_from datetime = null,
	@d_to datetime = null
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @d_from is null set @d_from = dbo.today() - 1
	if @d_to is null set @d_to = dbo.today() - 1

	declare @error varchar(200)
	if not exists(select 1 from ccy_rates_cross where d_doc = @d_from)
	begin
		set @error = concat('Отсутствуют курсы валют на дату ', convert(varchar, @d_from, 104), '. Формирование отчёта приостановлено.')
		raiserror(@error, 16, 1)
		return
	end

	if not exists(select 1 from ccy_rates_cross where d_doc = @d_to)
	begin
		set @error = concat('Отсутствуют курсы валют на дату ', convert(varchar, @d_to, 104), '. Формирование отчёта приостановлено.')
		raiserror(@error, 16, 1)
		return
	end

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

-- @result
	declare @result table(
		account_id int index ix_accounts, 
		value_start decimal(18,2),
		value_start_ccy decimal(18,2),
		value_in decimal(18,2),
		value_out decimal(18,2),
		value_turn_ccy decimal(18,2),
		value_end decimal(18,2),
		value_end_ccy decimal(18,2),
		value_ccydiff decimal(18,2) default 0
		)

-- result
	;with starts as (
		select f.account_id, 
			sum(f.value_ccy) as value_start_ccy,
			sum(f.value_rur) as value_start
		from findocs f
			join @subjects s on s.id = f.subject_id
		where (@subject_id is null or f.subject_id = @subject_id)
			and f.d_doc < @d_from
            and f.status_id >= 0
		group by f.account_id
		)
	, turns as (
		select f.account_id, 
			sum(case when value_rur > 0 then value_rur end) as value_in,
			sum(case when value_rur < 0 then value_rur end) as value_out,
			sum(value_ccy) as value_turn_ccy 
		from findocs f
			join @subjects s on s.id = f.subject_id
		where (@subject_id is null or f.subject_id = @subject_id)
			and f.d_doc between @d_from and @d_to
            and f.status_id >= 0
		group by f.account_id
		)
	insert into @result(account_id, value_start, value_start_ccy, value_in, value_out, value_turn_ccy)
	select account_id, 
		isnull(sum(value_start),0),
		isnull(sum(value_start_ccy),0),
		isnull(sum(value_in),0),
		isnull(sum(value_out),0),
		isnull(sum(value_turn_ccy),0)
	from (
		select account_id, value_start, value_start_ccy, 0.00 as value_in, 0.00 as value_out, 0.00 as value_turn_ccy
		from starts

		union all
		select account_id, 0, 0, value_in, value_out, value_turn_ccy
		from turns
		) u
	group by account_id

	update x set
		value_start = value_start + isnull(a.saldo_in,0),
		value_start_ccy = value_start_ccy + isnull(a.saldo_in,0)
	from @result x
		join findocs_accounts a on a.account_id = x.account_id

	update @result
	set value_end = value_start + value_in + value_out,
		value_end_ccy = value_start_ccy + value_turn_ccy

	declare @value_start_rur decimal(18,2),
			@value_end_rur decimal(18,2)

	update r
	set @value_start_rur = value_start_ccy * cr1.rate,
		@value_end_rur = value_end_ccy * cr2.rate,
		value_ccydiff = @value_end_rur - (r.value_in + r.value_out) - @value_start_rur,
		value_start = @value_start_rur,
		value_end = @value_end_rur
	from @result r
		join findocs_accounts a on a.account_id = r.account_id
		join ccy_rates_cross cr1 on cr1.d_doc = @d_from and cr1.from_ccy_id = a.ccy_id and cr1.to_ccy_id = 'rur'
		join ccy_rates_cross cr2 on cr2.d_doc = @d_to and cr2.from_ccy_id = a.ccy_id and cr2.to_ccy_id = 'rur'
	where a.ccy_id <> 'rur'

	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

	select 
		S.NAME AS SUBJECT_NAME,
		A2.NAME AS ACCOUNT_GROUP_NAME,
		A.NAME AS ACCOUNT_NAME,
		A.CCY_ID,
		R.VALUE_START,
		R.VALUE_IN,
		R.VALUE_OUT,
		R.VALUE_END,
		R.VALUE_CCYDIFF
	from @result r
		join findocs_accounts a on a.account_id = r.account_id
			left join findocs_accounts a2 on a2.account_id = a.parent_id
			join subjects s on s.subject_id = a.subject_id
	where abs(value_start) + abs(value_in) + abs(value_out) + abs(value_end) + abs(value_ccydiff) >= 0.01
		and a.name <> @vat_refund
end
go
