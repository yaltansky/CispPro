if object_id('mfr_pdm_sync') is not null drop proc mfr_pdm_sync
go
create proc mfr_pdm_sync
	@mol_id int,
	@map app_mapids2 readonly,
	@parts varchar(100) = null -- указать через запятую
as
begin
    set nocount on;

	create table #pdm_map(source_id int index ix1, target_id int index ix2)
	
    insert into #pdm_map(source_id, target_id)
    select old_id, new_id from @map

	-- MFR_PDM_ITEMS
		if charindex('items', isnull(@parts, 'items')) > 0
			insert into mfr_pdm_items(
				pdm_id, item_id, item_type_id, is_buy, unit_name, q_netto, q_brutto, add_mol_id, is_deleted
				)
			select 
				i.target_id, x.item_id, x.item_type_id, x.is_buy, x.unit_name, x.q_netto, x.q_brutto, @mol_id, x.is_deleted
			from mfr_pdm_items x
				join #pdm_map i on i.source_id = x.pdm_id
			where not exists(select 1 from mfr_pdm_items where pdm_id = i.target_id)

    -- MFR_PDM_DOCS
		if charindex('docs', isnull(@parts, 'docs')) > 0
			insert into mfr_pdm_docs(
				pdm_id, number, name, note, url, add_mol_id, is_deleted
				)
			select 
				i.target_id, number, name, note, url, @mol_id, is_deleted
			from mfr_pdm_docs x
				join #pdm_map i on i.source_id = x.pdm_id
            where x.number != 'httpref' -- see tg_sdocs_mfr_pdm_attrs trigger

    -- MFR_PDM_OPERS
		if charindex('opers', isnull(@parts, 'opers')) > 0
		begin
			EXEC SYS_SET_TRIGGERS 0

            delete x from mfr_pdm_opers x, #pdm_map i where x.pdm_id = i.target_id
            delete x from mfr_pdm_opers_executors x, #pdm_map i where x.pdm_id = i.target_id
            delete x from mfr_pdm_opers_resources x, #pdm_map i where x.pdm_id = i.target_id

			-- MFR_PDM_OPERS
				create table #pdm_map_opers(
					old_oper_id int index ix1, oper_id int, pdm_id int,
					index ix2 (old_oper_id, pdm_id)
					)

				insert into mfr_pdm_opers(
					pdm_id, variant_number, operkey, number, 
					reserved, place_id, type_id, work_type_id, name, part_q, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, is_deleted, count_executors, count_resources, is_first, is_last, count_workers
					)
					output inserted.reserved, inserted.oper_id, inserted.pdm_id into #pdm_map_opers
				select 
					i.target_id, x.variant_number, x.operkey, x.number, 
					x.oper_id, x.place_id, x.type_id, x.work_type_id, x.name, x.part_q, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.is_deleted, x.count_executors, x.count_resources, x.is_first, x.is_last, x.count_workers
				from mfr_pdm_opers x
					join #pdm_map i on i.source_id = x.pdm_id

			-- MFR_PDM_OPERS_EXECUTORS
				insert into mfr_pdm_opers_executors(
					pdm_id, oper_id, post_id, duration_wk, duration_wk_id, rate_price, note, add_mol_id, is_deleted
					)
				select 
					m.pdm_id, m.oper_id, x.post_id, x.duration_wk, x.duration_wk_id, x.rate_price, x.note, @mol_id, x.is_deleted
				from mfr_pdm_opers_executors x
					join #pdm_map i on i.source_id = x.pdm_id
					join #pdm_map_opers m on m.old_oper_id = x.oper_id and m.pdm_id = i.target_id

			-- MFR_PDM_OPERS_RESOURCES
				insert into mfr_pdm_opers_resources(
					pdm_id, oper_id, resource_id, loading, note, add_mol_id, is_deleted, loading_price, loading_value
					)
				select 
					m.pdm_id, m.oper_id, x.resource_id, x.loading, x.note, @mol_id, x.is_deleted, x.loading_price, x.loading_value
				from mfr_pdm_opers_resources x
					join #pdm_map i on i.source_id = x.pdm_id
					join #pdm_map_opers m on m.old_oper_id = x.oper_id and m.pdm_id = i.target_id
			
			EXEC SYS_SET_TRIGGERS 1
		end
		
	exec drop_temp_table '#pdm_map,#pdm_map_opers'
end
GO

-- print dbo.sys_query_insert('mfr_pdm_opers_executors', null, null, 'x', 1)