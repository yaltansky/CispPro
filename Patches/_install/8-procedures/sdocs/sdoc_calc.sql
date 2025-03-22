if object_id('sdoc_calc') is not null drop procedure sdoc_calc
go
create proc sdoc_calc	
	@mol_id int,
	@doc_id int = null,
    @docs app_pkids readonly
as
begin

	set nocount on;

	declare @value_pure decimal(18,2)

    create table #sdoc_calc_docs(id int primary key)
    insert into #sdoc_calc_docs select id from @docs

	-- price, value_nds ...
		update dt set			
			@value_pure = price_pure * quantity,
			nds_ratio = isnull(nds_ratio, 0.2),
			price = price_pure * (1 + nds_ratio),			
			value_nds = @value_pure * nds_ratio,
			value_pure = @value_pure,
			value_ccy = @value_pure + value_nds,
			value_rur = (@value_pure + value_nds) * isnull(cr.rate, 1)
		from sdocs_products dt
			join sdocs d on d.doc_id = dt.doc_id
			left join ccy_rates_cross cr on cr.d_doc = d.d_doc and cr.from_ccy_id = d.ccy_id and cr.to_ccy_id = 'rur'
		where 
            (@doc_id is not null and d.doc_id = @doc_id)
            or (@doc_id is null and d.doc_id in (select id from #sdoc_calc_docs))
	
	-- totals
		update d set 
			value_ccy = dt.value_ccy,
			value_rur = dt.value_rur
		from sdocs d
			left join (
				select doc_id,
				sum(value_ccy) as value_ccy,
				sum(value_rur) as value_rur
			from sdocs_products dt
			group by doc_id
			) dt on dt.doc_id = d.doc_id
		where 
            (@doc_id is not null and d.doc_id = @doc_id)
            or (@doc_id is null and d.doc_id in (select id from #sdoc_calc_docs))

    if @doc_id is not null
    begin
        -- build pay_conditions
            declare @prefixes table(milestone_id int primary key, short_name varchar(16))
                insert into @prefixes(milestone_id, short_name)
                select milestone_id, short_name from sdocs_type1_milestones

            declare @pay_conditions varchar(max)

            update x
            set @pay_conditions = (
                    select concat(
                        map.short_name,
                        case when m.date_lag > 0 then '+' else '-' end,
                        m.date_lag,
                        case when m.date_lag is not null then 'д' end,
                        case when m.ratio > 0 then '*' end,
                        cast(m.ratio * 100 as int),
                        case when m.ratio > 0 then '%' end,
                        ';') [text()] 
                    from sdocs_milestones m
                        left join @prefixes map on map.milestone_id = m.milestone_id
                    where m.doc_id = x.doc_id
                        and m.ratio > 0	
                    for xml path('')
                    ),
                pay_conditions = left(@pay_conditions, 100),
                update_date = getdate(),
                update_mol_id = @mol_id
            from sdocs x
            where x.doc_id = @doc_id

        -- calc access
            exec sdoc_calc_access @doc_id = @doc_id
    end

    exec drop_temp_table '#sdoc_calc_docs'
end
go
