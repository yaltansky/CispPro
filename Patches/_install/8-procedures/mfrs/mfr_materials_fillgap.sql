/***
    CREATE TABLE MFR_R_MATERIALS_GAP(
        MFR_DOC_ID INT,
        D_PLAN DATE,
        CONTENT_ID INT,
        ITEM_ID INT,
        UNIT_NAME VARCHAR(20),
        Q FLOAT,
        LEFT_Q FLOAT
        )
***/
if object_id('mfr_materials_fillgap') is not null drop proc mfr_materials_fillgap
go
create proc mfr_materials_fillgap
as
begin

	set nocount on;

	declare @docs as app_pkids
	insert into @docs select doc_id from mfr_sdocs where status_id >= 0

	-- tables
		create table #materials(
			mat_row_id int identity primary key,
			mfr_doc_id int,
            sort_number int,
			d_plan date,
            content_id int,
            item_id int index ix_item,
            unit_name varchar(20),
			value float
			)
			
		create table #lzk(
			lzk_row_id int identity primary key,
			doc_id int,
			d_doc date,
            item_id int index ix_item,
            unit_name varchar(20),
			value float
			)

		create table #result(		
			mat_row_id int index ix_cal_row,
			lzk_row_id int index ix_ord_row,
			d_doc date,
            d_plan date,
			mfr_doc_id int,
			content_id int index ix_content,
            item_id int,
            unit_name varchar(20),
			material_q float,
            lzk_q float,
			slice varchar(20)
			)	
	
    -- get data

        -- #materials
            insert into #materials(mfr_doc_id, sort_number, d_plan, content_id, item_id, unit_name, value)
            select distinct mfr_doc_id, sort_number, d_plan, content_id, item_id, unit_name, q_brutto_product
            from (
                select distinct 
                    mfr_doc_id = cm.mfr_doc_id, 
                    sort_number = case when cp.status_id in (100,200) then 0 else 1 end,
                    d_plan = isnull(cm.opers_to_plan, mfr.d_issue_plan),
                    cm.content_id, cm.item_id, cm.unit_name, cm.q_brutto_product
                from sdocs_mfr_contents cm
                    join @docs i on i.id = cm.mfr_doc_id
                    join mfr_sdocs mfr on mfr.doc_id = cm.mfr_doc_id
                    join sdocs_mfr_contents ci on ci.mfr_doc_id = cm.mfr_doc_id and ci.product_id = cm.product_id
                        and cm.node.IsDescendantOf(ci.node) = 1
                    join sdocs_mfr_contents cp on cp.mfr_doc_id = cm.mfr_doc_id and cp.product_id = cm.product_id and cp.child_id = cm.parent_id
                where cm.is_buy = 1
                    and ci.status_id in (100,200)
                    -- and cm.item_id = 1559
                ) m
            order by 
                item_id, sort_number desc, d_plan desc, content_id desc

        -- #products
            create table #products(product_id int primary key, unit_name varchar(20))
                insert into #products(product_id, unit_name)
                select item_id, max(unit_name) from #materials group by item_id

            -- units.#materials
                declare @koef float
                update x set 
                    @koef = coalesce(uk.koef, dbo.product_ukoef(x.unit_name, p.unit_name)),
                    unit_name = case when @koef is not null then p.unit_name else x.unit_name end,
                    value = x.value * coalesce(@koef, 1)
                from #materials x					
                    join #products p on p.product_id = x.item_id
                    left join products_ukoefs uk on uk.product_id = x.item_id and uk.unit_from = x.unit_name and uk.unit_to = p.unit_name
                where x.unit_name <> p.unit_name

        -- #lzk
            insert into #lzk(doc_id, d_doc, item_id, unit_name, value)
            select sp.doc_id, sd.d_doc, sp.product_id, u.name, sp.quantity
            from sdocs_products sp
                join sdocs sd on sd.doc_id = sp.doc_id and sd.type_id = 12
                join products_units u on u.unit_id = sp.unit_id
                join #products p on p.product_id = sp.product_id
            where sd.status_id >= 0
            order by sp.product_id, sd.d_doc desc, sd.doc_id desc

            -- units.#lzk
                update x set 
                    @koef = coalesce(uk.koef, dbo.product_ukoef(x.unit_name, p.unit_name)),
                    unit_name = case when @koef is not null then p.unit_name else x.unit_name end,
                    value = x.value * coalesce(@koef, 1)
                from #lzk x
                    join #products p on p.product_id = x.item_id
                    left join products_ukoefs uk on uk.product_id = x.item_id and uk.unit_from = x.unit_name and uk.unit_to = p.unit_name
                where x.unit_name <> p.unit_name

    -- FIFO: #materials + #lzk
		declare @fid uniqueidentifier set @fid = newid()

        insert into #result(
			mat_row_id, lzk_row_id, item_id, content_id, mfr_doc_id, d_plan, d_doc, unit_name, material_q, lzk_q, slice
			)
		select
			r.mat_row_id, p.lzk_row_id,
			r.item_id, r.content_id, r.mfr_doc_id, r.d_plan, p.d_doc,
			r.unit_name, f.value, f.value,
            'mix'
		from #materials r
			join #lzk p on p.item_id = r.item_id
			cross apply dbo.fifo(@fid, p.lzk_row_id, p.value, r.mat_row_id, r.value) f
		order by r.mat_row_id, p.lzk_row_id

    -- left (materials)
        insert into #result(mat_row_id, item_id, content_id, mfr_doc_id, d_plan, unit_name, material_q, slice)
		select x.mat_row_id, x.item_id, x.content_id, x.mfr_doc_id, x.d_plan, x.unit_name, f.value, 'left'
		from dbo.fifo_left(@fid) f
			join #materials x on x.mat_row_id = f.row_id
		where f.value > 0

		insert into #result(mat_row_id, item_id, content_id, mfr_doc_id, d_plan, unit_name, material_q, slice)
		select x.mat_row_id, x.item_id, x.content_id, x.mfr_doc_id, x.d_plan, x.unit_name, x.value, 'left'
		from #materials x
		where not exists(select 1 from #result where mat_row_id = x.mat_row_id)

        truncate table mfr_r_materials_gap

        insert into mfr_r_materials_gap(mfr_doc_id, d_plan, content_id, item_id, unit_name, q, left_q)
        select r.mfr_doc_id, r.d_plan, r.content_id, r.item_id, r.unit_name, c.q_brutto_product, r.material_q
        from #result r
            join sdocs_mfr_contents c on c.content_id = r.content_id
        where r.slice = 'left'

        exec fifo_clear @fid

    exec drop_temp_table '#materials,#lzk,#result'

end
go

/***
    CLEAR STATE

    declare @tmp as app_pkids
    insert into @tmp select content_id from sdocs_mfr_contents where is_buy = 1 and item_id = 1559

    exec sys_set_triggers 0

        update sdocs_mfr_opers set status_id = 0, progress = 0
        where content_id in (select id from @tmp)

        update sdocs_mfr_contents set status_id = 0, is_manual_progress = 0, note = null
        where content_id in (select id from @tmp)

    exec sys_set_triggers 1
***/

-- exec mfr_materials_fillgap
-- select count(distinct content_id) from mfr_r_materials_gap

/***
    ЭТАП 2: пометить материалы как обеспеченные через 100% выполнения

    exec sys_set_triggers 0

        update sdocs_mfr_opers set status_id = 100, progress = 1
        where content_id in (select distinct content_id from mfr_r_materials_gap)

        update sdocs_mfr_contents set status_id = 100, is_manual_progress = 1, note = 'fixed'
        where content_id in (select distinct content_id from mfr_r_materials_gap)

    exec sys_set_triggers 1
***/

/***
    ЭТАП 3: пересчёт регистра материалов
***/

/***
    ПРОВЕРКА

	declare @docs as app_pkids
	insert into @docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id between 0 and 99

    select distinct cm.content_id
    from sdocs_mfr_contents cm with(nolock)
        join @docs i on i.id = cm.mfr_doc_id
        join sdocs_mfr_contents ci with(nolock) on ci.mfr_doc_id = cm.mfr_doc_id and ci.product_id = cm.product_id
            and cm.node.IsDescendantOf(ci.node) = 1
    where cm.is_buy = 1
        and ci.status_id = 100
        and isnull(cm.status_id,0) <> 100

***/
