if object_id('sdoc_products_details_master') is not null drop procedure sdoc_products_details_master
go
-- exec sdoc_products_details_master 7132073
create proc sdoc_products_details_master
	@detail_id int
as
begin
    set nocount on;

    -- prepare
        declare @type_id int, @doc_id int, @product_id int, @unit_name varchar(20)
        
        select @doc_id = doc_id, @product_id = product_id, @unit_name = u.name
        from sdocs_products x
            join products_units u on u.unit_id = x.unit_id
        where detail_id = @detail_id

        select @type_id = type_id from sdocs where doc_id = @doc_id

        select top 0 *,
            SORT_ID = CAST(NULL AS INT),
            MFR_DOC_ID = CAST(NULL AS INT),
            PRODUCT_ID = CAST(NULL AS INT),
            UNIT_NAME = CAST(NULL AS VARCHAR(20)),
            D_MFR_TO = CAST(NULL AS DATE)
        into #details from sdocs_products_details

    -- get data
        -- -- связанная потребность
        --     if @type_id in (8,9) -- счета, приходы
        --         insert into #details(mfr_doc_id, d_mfr_to, quantity, unit_name, note)
        --         select mfr_doc_id, min(d_mfr_to), sum(q_mfr), unit_name, '#регистр '
        --         from mfr_r_provides
        --         where item_id = @product_id
        --             and q_mfr > 0
        --             and @doc_id in (id_invoice, id_ship)
        --         group by mfr_doc_id, unit_name
        --         order by min(d_mfr_to)

        -- не связанная потребность
            insert into #details(mfr_doc_id, d_mfr_to, quantity, unit_name, note)
            select top 1000
                mfr_doc_id,
                min(d_mfr_to),
                quantity = sum(q_mfr),
                unit_name,
                '#регистр '
            from mfr_r_provides
            where item_id = @product_id
                and q_mfr > 0
                -- and id_invoice is null
                -- and id_ship is null
                -- and id_job is null
                and slice != '100%'
            group by mfr_doc_id, unit_name
            order by min(d_mfr_to)

    -- -- sort
    --     UPDATE #DETAILS SET SORT_ID = ID, ADD_DATE = GETDATE(), PRODUCT_ID = @PRODUCT_ID
        ALTER TABLE #DETAILS DROP COLUMN ID

    -- mfr_number
        update x set 
            doc_id = @doc_id,
            detail_id = @detail_id,
            product_id = @product_id,
            mfr_number = mfr.number,
            note = concat(x.note, 'ПДО=', convert(varchar(10), x.d_mfr_to, 20))
        from #details x
            join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id

	-- convert units
		update x set 
			quantity = x.quantity * coalesce(uk.koef, dbo.product_ukoef(x.unit_name, @unit_name), 1)
		from #details x					
			left join products_ukoefs uk on uk.product_id = x.product_id and uk.unit_from = x.unit_name and uk.unit_to = @unit_name

    -- select
        SELECT ID = CAST(0 AS INT), * FROM #DETAILS ORDER BY D_MFR_TO, MFR_NUMBER
end
go
