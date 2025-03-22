if object_id('mfr_reps_materials_turns') is not null drop proc mfr_reps_materials_turns
go
-- exec mfr_reps_materials_turns 1000, @d_from = '2024-09-01'
create proc mfr_reps_materials_turns
	@mol_id int,
	@d_from date = null,
	@d_to date = null,
	@status_id int = 100,
	@search varchar(max) = null,
    @recalc bit = 1
as
begin
	set nocount on;

	set @d_from = isnull(@d_from, '1900-01-01')
	set @d_to = isnull(@d_to, dbo.today())
	set @status_id = isnull(@status_id, 100)

	exec mfr_items_prices_calc;

    exec sdocs_stocks_turns_calc
        @mol_id = @mol_id,
        @d_from = @d_from,
        @d_to = @d_to,
        @status_id = @status_id,
        @search = @search,
        @enforce = @recalc;

	-- result
		declare @attr_keeper int = (select top 1 attr_id from prodmeta_attrs where code = 'закупка.КодКладовщика')

		select 
			ACC_REGISTER_NAME = ACC.NAME,
			PRINCIPAL_DOGOVOR_NAME = DPD.NAME,
			PRODUCT_GROUP1_NAME = PG1.NAME,
			PRODUCT_GROUP2_NAME = PG2.NAME,
			PRODUCT_NAME = P.NAME,
			KEEPER_NAME = pa.ATTR_VALUE,
			X.PRODUCT_ID,
			cast(null as int) as DOC_ID,
			cast(null as date) as D_DOC,
			cast(null as varchar(50)) as NUMBER,
			UNIT_NAME = LOWER(LTRIM(u.NAME)),
			X.Q_START,
			V_START = CAST(NULL AS FLOAT),
			X.Q_INPUT,
			V_INPUT = CAST(NULL AS FLOAT),
			X.Q_OUTPUT,
			V_OUTPUT = CAST(NULL AS FLOAT),
			X.Q_END,
			V_END = CAST(NULL AS FLOAT)
		into #result
		from sdocs_r_stocks_turns x
			left join accounts_registers acc on acc.acc_register_id = x.acc_register_id
			left join docs_principals_dogovors dpd on dpd.document_id = x.principal_dogovor_id
			join products p on p.product_id = x.product_id
			left join v_products_groups pg1 on pg1.product_id = x.product_id
			left join v_products_subgroups pg2 on pg2.product_id = x.product_id
			left join products_attrs pa on pa.product_id = x.product_id and pa.attr_id = @attr_keeper
            left join products_units u on u.unit_id = x.unit_id
		where x.mol_id = @mol_id
            and (
                abs(isnull(x.q_start,0)) > 0.001
                or abs(isnull(x.q_input,0)) > 0.001
                or abs(isnull(x.q_output,0)) > 0.001
                or abs(isnull(x.q_end,0)) > 0.001
            );

		create index ix__result on #result(product_id);

	-- цены
		declare @koef float

		update x set
			@koef = 1.0 / case when x.unit_name = u.name then 1.0 else isnull(uk.koef,1) end,
			v_start = x.q_start * pr.price * @koef,
			v_input = x.q_input * pr.price * @koef,
			v_output = x.q_output * pr.price * @koef,
			v_end = x.q_end * pr.price * @koef
		from #result x
			join mfr_items_prices pr on pr.product_id = x.product_id
				join products_units u on u.unit_id = pr.unit_id
				left join products_ukoefs uk on uk.product_id = pr.product_id and uk.unit_from = u.name and uk.unit_to = x.unit_name

	-- final
		select *,
			PRODUCT_HID = CONCAT('#', PRODUCT_ID)
		from #result
		
        exec drop_temp_table '#result';
end
go
