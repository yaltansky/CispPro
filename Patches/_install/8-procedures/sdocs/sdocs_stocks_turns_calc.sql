if object_id('sdocs_stocks_turns_calc') is not null drop proc sdocs_stocks_turns_calc
go
-- exec sdocs_stocks_turns_calc 1000
create proc sdocs_stocks_turns_calc
	@mol_id int,
    @d_from date = null,
    @d_to date = null,
    @status_id int = 100,
    @search varchar(max) = null,
    @enforce bit = 0
as
begin
    set nocount on;
    
    declare @today date = dbo.today()
    if @d_from is null set @d_from = dateadd(d, -datepart(d, @today) + 1, @today)
    if @d_to is null set @d_to = dateadd(d, -1, dateadd(m, 1, @d_from))

    declare @d_from_prev date = dateadd(d, -1, @d_from);

	declare @products table(id int primary key);

	if nullif(@search, '') is not null
	begin
		set @search = '%' + replace(@search, ' ', '%') + '%'

		insert into @products
		select p.product_id
		from products p
			left join v_products_groups pg1 on pg1.product_id = p.product_id
			left join v_products_subgroups pg2 on pg2.product_id = p.product_id
		where p.name like @search
			or (pg1.name is not null and pg1.name like @search)
			or (pg2.name is not null and pg2.name like @search)
	end;

	declare @filter_products bit = case when exists(select 1 from @products) then 1 else 0 end

	-- tables
		create table #data(
			product_id int index ix_product,
			acc_register_id int,
			principal_dogovor_id int,
            stock_id int,
            addr_id int,
			doc_id int,
            d_doc date,
            number varchar(50),
			unit_from_id int,
			unit_id int,
			quantity float,
			index ix_group(product_id)
		)	

		create table #turn(
            product_id int index ix_product,
            turn_type_id int, -- 0 входящие, 1 обороты, 2 исходящие
			acc_register_id int,
			principal_dogovor_id int,
            stock_id int,
            addr_id int,
			doc_id int,
			d_doc date,
			number varchar(50),
			unit_id int,
			q_start float,
			q_input float,
			q_output float,
			q_end float
		)	

	-- подготовка данных
        -- входящие
		insert into #data(
            product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, 
            d_doc, number, unit_from_id, unit_id, quantity
            )
		select
            product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id,
            @d_from_prev,
            'Входящие', 
            unit_id, unit_id,
            sum(quantity)
        from ( 
            select 
                sp.product_id,
                case when mfr.doc_id is not null then mfr.acc_register_id else sd.acc_register_id end as acc_register_id,
                sd.principal_dogovor_id, 
                coalesce(ad.stock_id, sd.stock_id) as stock_id,
                spd.stock_addr_id as addr_id,
                tp.direction * coalesce(spd.quantity, sp.quantity) as quantity,
                sp.unit_id
            from sdocs_products sp
                join sdocs sd on sd.doc_id = sp.doc_id
                    join sdocs_types tp on tp.type_id = sd.type_id
                left join sdocs_products_details spd on spd.detail_id = sp.detail_id
                    left join sdocs_stocks_addrs ad on ad.addr_id = spd.stock_addr_id
                    left join mfr_sdocs mfr on mfr.number = coalesce(spd.mfr_number, sp.mfr_number)
            where tp.direction != 0
                and sd.status_id >= @status_id
                and sd.d_doc < @d_from
                and (
                    sd.type_id = 100 -- инвентаризация с любым знаком
                    or (sd.type_id != 100 and sp.quantity > 0) -- иначе только + (чтобы избежать "кривых" данных)
                    )
                and (@filter_products = 0 or sp.product_id in (select id from @products))
            ) x
        group by 
            product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, unit_id;

        insert into #data(
            product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id,
            doc_id, d_doc, number, unit_from_id, unit_id, quantity
            )
        select
            product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, doc_id, d_doc, number, unit_id, unit_id,
            sum(quantity)
        from (
            select 
                sp.product_id,
                case when mfr.doc_id is not null then mfr.acc_register_id else sd.acc_register_id end as acc_register_id,
                sd.principal_dogovor_id, 
                coalesce(ad.stock_id, sd.stock_id) as stock_id,
                spd.stock_addr_id as addr_id,
                sd.doc_id,
                sd.d_doc,
                sd.number,
                tp.direction * coalesce(spd.quantity, sp.quantity) as quantity,
                sp.unit_id
            from sdocs_products sp
                join sdocs sd on sd.doc_id = sp.doc_id
                    join sdocs_types tp on tp.type_id = sd.type_id
                left join sdocs_products_details spd on spd.detail_id = sp.detail_id
                    left join sdocs_stocks_addrs ad on ad.addr_id = spd.stock_addr_id
                    left join mfr_sdocs mfr on mfr.number = coalesce(spd.mfr_number, sp.mfr_number)
            where tp.direction != 0
                and sd.status_id >= @status_id
                and sd.d_doc between @d_from and @d_to
                and (
                    sd.type_id = 100 -- инвентаризация с любым знаком
                    or (sd.type_id != 100 and sp.quantity > 0) -- иначе только + (чтобы избежать "кривых" данных)
                    )
                and (@filter_products = 0 or sp.product_id in (select id from @products))
            ) x
        group by
            product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, doc_id, d_doc, number, unit_id;

	-- единицы измерения
		update x set unit_id = isnull(p.unit_id, pp.unit_id)
		from #data x
			join products p on p.product_id = x.product_id
			join (
				select product_id, unit_id = min(unit_from_id) from #data
				group by product_id
			) pp on pp.product_id = x.product_id

		update x set 
			quantity = x.quantity * uk.koef
        from #data x
        	join products_units u1 on u1.unit_id = x.unit_from_id
			join products_units u2 on u2.unit_id = x.unit_id
			join products_ukoefs uk on uk.product_id = x.product_id and uk.unit_from = u1.name and uk.unit_to = u2.name
    
	-- входящий остаток
		insert into #turn(
            turn_type_id, product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, d_doc, number, unit_id, q_start
            )
		select
			0,
            product_id,
			acc_register_id,
            principal_dogovor_id,
			stock_id,
			addr_id,
			@d_from,
			'ВхОстаток',		
			unit_id,
			sum(quantity)			
		from #data x
		where d_doc < @d_from
		group by product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, unit_id

	-- обороты
		insert into #turn(
            turn_type_id, product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, doc_id, d_doc, number, unit_id, q_input, q_output
            )
		select
			1,
            product_id,
			acc_register_id,
            principal_dogovor_id,
			stock_id,
			addr_id,
			doc_id,
			d_doc,
			number,
			unit_id,
			case when quantity > 0 then quantity end,
			case when quantity < 0 then -quantity end
		from #data
		where d_doc between @d_from and @d_to

    -- исходящий остаток
        insert into #turn(
            turn_type_id, product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, d_doc, number, unit_id, q_end
            )
        select
            2,
            product_id,
            acc_register_id,
            principal_dogovor_id,
            stock_id,
            addr_id,
            @d_to,
            'ИсхОстаток',		
            unit_id,
            sum(quantity)			
        from #data
        group by product_id, acc_register_id, principal_dogovor_id, stock_id, addr_id, unit_id

    -- final
        delete from sdocs_r_stocks_turns where mol_id = @mol_id

        insert into sdocs_r_stocks_turns(
            mol_id, acc_register_id, principal_dogovor_id, product_id, stock_id, addr_id, turn_type_id, doc_id, d_doc, number, unit_id, q_start, q_input, q_output, q_end
            )
        select
            @mol_id, acc_register_id, principal_dogovor_id, product_id, stock_id, addr_id, turn_type_id, doc_id, d_doc, number, unit_id, q_start, q_input, q_output, q_end
        from #turn

end
go
