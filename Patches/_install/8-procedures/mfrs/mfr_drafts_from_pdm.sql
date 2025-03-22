if object_id('mfr_drafts_from_pdm') is not null drop proc mfr_drafts_from_pdm
go
create proc mfr_drafts_from_pdm
	@mol_id int,
	@start_draft_id int
as
begin
    set nocount on;

	declare	@mfr_doc_id int, @product_id int, @start_pdm_id int
		select 
			@mfr_doc_id = mfr_doc_id,
			@product_id = product_id,
			@start_pdm_id = pdm_id
		from mfr_drafts where draft_id = @start_draft_id

	-- tables
		create table #drafts(draft_id int primary key)
		create table #created(draft_id int)

	-- apply pdm to drafts
		declare @drafts app_pkids
		insert into @drafts select @start_draft_id
		exec mfr_drafts_from_pdm;2 @mol_id = @mol_id, @drafts = @drafts, @enforce = 1

	-- loop
		declare @level int = 0
		declare @maxlevel int = 100

		while @level < @maxlevel -- страховка: не более N уровней
		begin
			insert into #drafts(draft_id)
			select distinct dd.draft_id from mfr_drafts_items di
				join mfr_drafts d on d.draft_id = di.draft_id
				join mfr_drafts dd on dd.mfr_doc_id = d.mfr_doc_id and dd.product_id = d.product_id
					and dd.item_id = di.item_id
			where d.draft_id in (select id from @drafts)

			if @@rowcount = 0 break -- добрались до нижнего уровня иерархии?
			set @level = @level + 1

			delete from @drafts; insert into @drafts select draft_id from #drafts
			exec mfr_drafts_from_pdm;2 @mol_id = @mol_id, @drafts = @drafts

            insert into #created select draft_id from #drafts
			truncate table #drafts
		end

    -- calc is_buy
        update mfr_drafts set is_buy =
            case
                when exists(select 1 from mfr_drafts_items where draft_id = mfr_drafts.draft_id and is_buy = 0)
                    or exists(select 1 from mfr_drafts_opers where draft_id = mfr_drafts.draft_id and work_type_id = 1) 
                    then 0 -- производим
                else 1 -- покупаем
            end
        where draft_id in (select distinct draft_id from #created)

    -- default part_q
        update mfr_drafts set part_q = isnull(part_q, 1)
        where draft_id in (select distinct draft_id from #created)

    -- read prices
        update x set
            unit_name = pr.unit_name,
            item_price0 = pr.price
        from mfr_drafts x
            join (
                select x.draft_id, 
                    x.unit_name,
                    price = pr.price 
                        / 
                        case 
                            when u.name = x.unit_name then 1.0 
                            else nullif(coalesce(uk.koef, dbo.product_ukoef(u.name, x.unit_name), 1), 0)
                        end
                from mfr_drafts x
                    join mfr_items_prices pr on pr.product_id = x.item_id
                        join products_units u on u.unit_id = pr.unit_id
                        left join products_ukoefs uk on uk.product_id = pr.product_id and uk.unit_from = u.name and uk.unit_to = x.unit_name
                where x.draft_id in (select distinct draft_id from #created)
            ) pr on pr.draft_id = x.draft_id

    -- read default attrs
        declare @узелРазмер int = (select top 1 attr_id from prodmeta_attrs where name = 'узел.Размер')
        declare @узелМассаОбъекта int = (select top 1 attr_id from prodmeta_attrs where name = 'узел.МассаОбъекта')
        insert into mfr_drafts_attrs(draft_id, attr_id, note)
        select distinct d.draft_id, pa.attr_id, pa.attr_value
        from mfr_drafts d
            join products_attrs pa on pa.product_id = d.item_id and pa.attr_id in (@узелРазмер, @узелМассаОбъекта)
        where d.draft_id in (select distinct draft_id from #created)
            and not exists(select 1 from mfr_drafts_attrs where draft_id = d.draft_id and attr_id = pa.attr_id)

    exec drop_temp_table '#drafts,#created'
end
go
-- helper: apply pdm
create proc mfr_drafts_from_pdm;2
	@mol_id int,
	@drafts app_pkids readonly,
	@sync_mode varchar(20) = 'all', -- all, opers
	@enforce bit = 0
as
begin
	if @sync_mode = 'opers' set @enforce = 1

	-- #bypdm_drafts
		create table #bypdm_drafts(id int primary key, route_number int default(1))
			insert into #bypdm_drafts(id) select draft_id 
			from mfr_drafts d
				join @drafts dd on dd.id = d.draft_id
			where @enforce = 1
				or (not exists(select 1 from mfr_drafts_items where draft_id = d.draft_id)
					and d.pdm_id is not null
					)

		if not exists(select 1 from #bypdm_drafts) return -- nothing todo

		update x set route_number = pdm.route_number
		from #bypdm_drafts x
			join mfr_drafts_pdm pdm on pdm.draft_id = x.id 
		where pdm.route_number is not null

	-- purge drafts
		if @sync_mode = 'all' delete from mfr_drafts_items where draft_id in (select id from #bypdm_drafts)
		delete from mfr_drafts_opers where draft_id in (select id from #bypdm_drafts)
		delete from mfr_drafts_opers_executors where draft_id in (select id from #bypdm_drafts)
		delete from mfr_drafts_opers_resources where draft_id in (select id from #bypdm_drafts)
	
    -- build items
		if @sync_mode = 'all'
        begin
            -- create temp
                create table #drafts_items(
                    draft_id int,
                    place_id int,
                    item_id int,
                    item_version varchar(30),
                    item_type_id int,
                    is_buy bit,
                    is_swap bit,
                    unit_name varchar(20),
                    q_netto float,
                    q_brutto float,
                    item_price0 decimal(18,2),
                    item_value0 decimal(18,2),
                    numbers varchar(max)
                )
            -- insert into temp
                insert into #drafts_items(draft_id, item_id, item_version, item_type_id, numbers, place_id, is_buy, unit_name, q_netto, q_brutto)
                select d.draft_id, pi.item_id, pi.item_version, pi.item_type_id, pi.numpos, pi.place_id, pi.is_buy, pi.unit_name, pi.q_netto, pi.q_brutto
                from mfr_pdm_items pi
                    join mfr_drafts d on d.pdm_id = pi.pdm_id
                        join #bypdm_drafts dd on dd.id = d.draft_id
                where isnull(pi.is_deleted,0) = 0
                    and (pi.pdm_option_id is null) -- no options
                    and (pi.parent_id is null and isnull(pi.has_childs,0) = 0) -- no analogs

            -- build options
                create table #drafts_options(draft_id int index ix_draft, pdm_option_id int)
                -- defaults
                insert into #drafts_options(draft_id, pdm_option_id)
                select d.draft_id, opt.pdm_option_id
                from mfr_pdm_options opt
                    join mfr_drafts d on d.pdm_id = opt.pdm_id
                        join #bypdm_drafts dd on dd.id = d.draft_id
                -- remove defaults (if specified else)
                delete x from #drafts_options x
                where draft_id in (
                    select d.draft_id
                    from mfr_drafts_pdm d
                        join #bypdm_drafts dd on dd.id = d.draft_id
                    where d.pdm_option_id is not null
                    )
                -- insert specisfied
                insert into #drafts_options(draft_id, pdm_option_id)
                select d.draft_id, d.pdm_option_id
                    from mfr_drafts_pdm d
                        join #bypdm_drafts dd on dd.id = d.draft_id
                where d.pdm_option_id is not null
                -- insert options
                insert into #drafts_items(draft_id, item_id, item_version, item_type_id, numbers, place_id, is_buy, unit_name, q_netto, q_brutto)
                select opt.draft_id, pi.item_id, pi.item_version, pi.item_type_id, pi.numpos, pi.place_id, pi.is_buy, pi.unit_name, pi.q_netto, pi.q_brutto
                from mfr_pdm_items pi
                    join #drafts_options opt on opt.pdm_option_id = pi.pdm_option_id
                where isnull(pi.is_deleted,0) = 0
            -- build analogs
                create table #drafts_analogs(draft_id int index ix_draft, analog_id int)
                -- defaults
                insert into #drafts_analogs(draft_id, analog_id)
                select d.draft_id, i.id
                from mfr_pdm_items i
                    join mfr_drafts d on d.pdm_id = i.pdm_id
                        join #bypdm_drafts dd on dd.id = d.draft_id
                where i.has_childs = 1
                    and isnull(i.is_deleted,0) = 0
                -- remove defaults (if specified else)
                delete x from #drafts_analogs x
                where draft_id in (
                    select d.draft_id
                    from mfr_drafts_pdm d
                        join #bypdm_drafts dd on dd.id = d.draft_id
                    where d.analog_id is not null
                    )
                -- insert specisfied
                insert into #drafts_analogs(draft_id, analog_id)
                select d.draft_id, d.analog_id
                    from mfr_drafts_pdm d
                        join #bypdm_drafts dd on dd.id = d.draft_id
                where d.analog_id is not null
                -- insert analogs
                insert into #drafts_items(draft_id, item_id, item_version, item_type_id, numbers, place_id, is_buy, unit_name, q_netto, q_brutto)
                select opt.draft_id, pi.item_id, pi.item_version, pi.item_type_id, pi.numpos, pi.place_id, pi.is_buy, pi.unit_name, pi.q_netto, pi.q_brutto
                from mfr_pdm_items pi
                    join #drafts_analogs opt on opt.analog_id = pi.id
                where isnull(pi.is_deleted,0) = 0
            -- insert items
                insert into mfr_drafts_items(draft_id, item_id, item_version, item_type_id, numbers, place_id, is_buy, unit_name, q_netto, q_brutto)
                select x.draft_id, x.item_id, x.item_version, x.item_type_id, x.numbers, x.place_id, x.is_buy, x.unit_name, x.q_netto, q_brutto
                from #drafts_items x
                    join products p on p.product_id = x.item_id
                order by x.draft_id, right(concat('0000000000', x.numbers), 10), p.name

            exec drop_temp_table '#drafts_items,#drafts_options,#drafts_analogs'
        end
    
    -- build opers, executors, resources
        if @sync_mode in ('all', 'opers')
        begin
            -- mfr_drafts_opers
                create table #map_opers(old_oper_id int index ix_oper, oper_id int, draft_id int)

                EXEC SYS_SET_TRIGGERS 0
                    insert into mfr_drafts_opers(
                        draft_id, reserved, 
                        number, place_id, type_id, work_type_id, name, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, count_executors, count_resources, is_first, is_last, count_workers, operkey
                        )
                        output inserted.reserved, inserted.oper_id, inserted.draft_id into #map_opers
                    select 
                        d.draft_id, x.oper_id, 
                        x.number, x.place_id, x.type_id, coalesce(x.work_type_id, p.work_type_id, 1), x.name, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.count_executors, x.count_resources, x.is_first, x.is_last, x.count_workers, x.operkey
                    from mfr_pdm_opers x
                        join mfr_drafts d on d.pdm_id = x.pdm_id
                            join #bypdm_drafts dd on dd.id = d.draft_id and dd.route_number = x.variant_number
                        left join mfr_places p on p.place_id = x.place_id
                EXEC SYS_SET_TRIGGERS 1

                update x set part_q = isnull(o.part_q, 1)
                from mfr_drafts x
                    join #bypdm_drafts dd on dd.id = x.draft_id
                    join (
                        select map.draft_id, part_q = max(o.part_q)
                        from mfr_pdm_opers o
                            join #map_opers map on map.old_oper_id = o.oper_id
                        group by map.draft_id
                    ) o on o.draft_id = x.draft_id
            -- mfr_drafts_opers_executors
                insert into mfr_drafts_opers_executors(
                    draft_id, oper_id, post_id, duration_wk, duration_wk_id, rate_price, note, add_mol_id
                    )
                select 
                    m.draft_id, m.oper_id, x.post_id, 
                    isnull(x.duration_wk, o.duration_wk), isnull(x.duration_wk_id, o.duration_wk_id), 
                    x.rate_price, x.note, @mol_id
                from mfr_pdm_opers_executors x		
                    join #map_opers m on m.old_oper_id = x.oper_id
                    join mfr_pdm_opers o on o.oper_id = x.oper_id
                where isnull(x.is_deleted,0) = 0
            -- mfr_drafts_opers_resources
                insert into mfr_drafts_opers_resources(
                    draft_id, oper_id, resource_id, loading, note, add_mol_id, loading_price, loading_value
                    )
                select 
                    m.draft_id, m.oper_id, x.resource_id, x.loading, x.note, @mol_id, x.loading_price, x.loading_value
                from mfr_pdm_opers_resources x
                    join #map_opers m on m.old_oper_id = x.oper_id
                where isnull(x.is_deleted,0) = 0
        end
    
    -- auto-append drafts	
        if @sync_mode = 'all'
        begin
            declare @today date = dbo.today()

            EXEC SYS_SET_TRIGGERS 0
                insert into mfr_drafts(mfr_doc_id, product_id, item_id, unit_name, pdm_id, is_buy, d_doc, number, status_id, add_mol_id)
                select distinct d.mfr_doc_id, d.product_id, di.item_id, di.unit_name, pdm.pdm_id, 0, @today, isnull(pdm.number, '-'), 0, @mol_id
                from mfr_drafts_items di
                    join mfr_drafts d on d.draft_id = di.draft_id
                        join #bypdm_drafts dd on dd.id = d.draft_id
                    left join mfr_pdms pdm on pdm.item_id = di.item_id 
                        and pdm.version_number = isnull(di.item_version, '1')
                        and pdm.is_deleted = 0
                where not exists(
                        select 1 from mfr_drafts where mfr_doc_id = d.mfr_doc_id and product_id = d.product_id
                            and item_id = di.item_id
                        )
            EXEC SYS_SET_TRIGGERS 1
        end

	exec drop_temp_table '#bypdm_drafts,#map_opers'
end
go
