if object_id('mfr_drafts_to_pdm') is not null drop proc mfr_drafts_to_pdm
go
create proc mfr_drafts_to_pdm
	@mol_id int,
    @option_version varchar(50), -- increment, last
	@drafts app_pkids readonly
as
begin

	declare @today date = dbo.today()
		
	-- topdm_drafts
        create table #topdm_drafts(pdm_id int index ix_pdm, draft_id int index ix_draft)
        insert into #topdm_drafts(draft_id) select id from @drafts

        if @option_version = 'last'
            update x set pdm_id = pdm.pdm_id
            from #topdm_drafts x
                join mfr_drafts d on d.draft_id = x.draft_id
                join (
                    select item_id, pdm_id = max(pdm_id)
                    from mfr_pdms
                    where status_id >= 0
                    group by item_id
                ) pdm on pdm.item_id = d.item_id
            where d.is_buy = 0 
                and d.is_deleted = 0

	-- mfr_pdms
		create table #map_pdm(pdm_id int index ix_pdm, draft_id int index ix_draft)

		insert into mfr_pdms(reserved, item_id, number, version_number, d_doc, status_id, add_mol_id)
		output inserted.pdm_id, inserted.reserved into #map_pdm
		select d.draft_id, d.item_id, d.number,
            concat('', isnull((select count(*) from mfr_pdms where item_id = d.item_id) + 1, 1)),
            @today, 0, @mol_id
		from mfr_drafts d
			join #topdm_drafts dd on dd.draft_id = d.draft_id
        where dd.pdm_id is null

        insert into #map_pdm(pdm_id, draft_id) select pdm_id, draft_id from #topdm_drafts
        where pdm_id is not null

	-- mfr_pdm_items
        delete from mfr_pdm_items where pdm_id in (select pdm_id from #topdm_drafts where pdm_id is not null)

		insert into mfr_pdm_items(pdm_id, item_id, item_type_id, NUMPOS, place_id, is_buy, unit_name, q_netto, q_brutto)
		select map.pdm_id, pi.item_id, pi.item_type_id, pi.numbers, pi.place_id, pi.is_buy, pi.unit_name, pi.q_netto, pi.q_brutto
		from mfr_drafts_items pi
			join #map_pdm map on map.draft_id = pi.draft_id
			join products p on p.product_id = pi.item_id
		order by pi.draft_id, right(concat('0000000000', pi.numbers), 10) , p.name

	EXEC SYS_SET_TRIGGERS 0

	-- mfr_pdm_opers
		create table #map_opers(old_oper_id int index ix_oper, oper_id int, pdm_id int)

        delete from mfr_pdm_opers where pdm_id in (select pdm_id from #topdm_drafts where pdm_id is not null)

        insert into mfr_pdm_opers(
			pdm_id, variant_number, reserved, 
			number, place_id, type_id, name, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, count_executors, count_resources, 
			is_first, is_last, count_workers, operkey
			)
			output inserted.reserved, inserted.oper_id, inserted.pdm_id into #map_opers
		select 
			map.pdm_id, 1, x.oper_id, 
			x.number, x.place_id, x.type_id, x.name, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.count_executors, x.count_resources, 
			isnull(x.is_first,0), isnull(x.is_last,0), x.count_workers, x.operkey
		from mfr_drafts_opers x
			join #map_pdm map on map.draft_id = x.draft_id

	-- mfr_pdm_opers_executors
		insert into mfr_pdm_opers_executors(
			pdm_id, oper_id, post_id, duration_wk, duration_wk_id, note, add_mol_id
			)
		select 
			m.pdm_id, m.oper_id, x.post_id, x.duration_wk, x.duration_wk_id, x.note, @mol_id
		from mfr_drafts_opers_executors x		
			join #map_opers m on m.old_oper_id = x.oper_id

	-- mfr_pdm_opers_resources
		insert into mfr_pdm_opers_resources(
			pdm_id, oper_id, resource_id, loading, note, add_mol_id, loading_price, loading_value
			)
		select 
			m.pdm_id, m.oper_id, x.resource_id, x.loading, x.note, @mol_id, x.loading_price, x.loading_value
		from mfr_drafts_opers_resources x
			join #map_opers m on m.old_oper_id = x.oper_id


	EXEC SYS_SET_TRIGGERS 1
	
	exec drop_temp_table '#topdm_drafts,#map_pdm,#map_opers'
end
go
