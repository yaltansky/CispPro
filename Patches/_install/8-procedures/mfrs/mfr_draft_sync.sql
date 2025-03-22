if object_id('mfr_draft_sync') is not null drop proc mfr_draft_sync
go
-- exec mfr_draft_sync @mol_id = 1000, @draft_id = 142639
create proc mfr_draft_sync
	@mol_id int,
	@draft_id int,
	@trace bit = 0
as
begin

	set nocount on;

    -- params
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

        declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
            ' @mol_id=', @mol_id,
            ' @draft_id=', @draft_id
            )
        exec tracer_log @tid, @tid_msg

        declare @doc_id int, @template_id int, @product_id int, @item_id int

        select 
            @doc_id = mfr_doc_id,
            @product_id	= product_id,
            @item_id = item_id,
            @template_id = template_id
        from mfr_drafts where draft_id = @draft_id

        -- TODO:: single product only!
        if (select count(*) from sdocs_products where doc_id = @doc_id) > 1
        begin
            raiserror('В текущем заказе больше одной строки в спецификации. Копирование из шаблона невозможно.', 16, 1)
            return
        end

        if @product_id is null set @product_id = (select top 1 product_id from sdocs_products where doc_id = @doc_id)
        
        if @template_id is null return -- nothing todo

        declare @docs app_pkids; insert into @docs select @doc_id

    BEGIN TRY
    BEGIN TRANSACTION

        -- print '@map'
            declare @map as table(
                item_id int primary key, draft_id int, new_draft_id int index ix_draft
                )
                insert into @map(item_id, draft_id)
                select d.item_id, min(d.draft_id)
                from sdocs_mfr_contents cp
                    join sdocs_mfr_contents c on c.mfr_doc_id = cp.mfr_doc_id and c.product_id = cp.product_id
                        and c.node.IsDescendantOf(cp.node) = 1
                        join mfr_drafts d on d.draft_id = c.draft_id
                where cp.mfr_doc_id = @template_id
                    and cp.item_id = @item_id
                    and d.is_deleted = 0
                group by d.item_id

                insert into @map(item_id, draft_id)
                select x.item_id, min(d.draft_id)
                from mfr_drafts_items x
                    join @map i on i.draft_id = x.draft_id				
                    join mfr_drafts xd on xd.draft_id = x.draft_id
                        join mfr_drafts d on d.mfr_doc_id = xd.mfr_doc_id and d.product_id = xd.product_id and d.item_id = x.item_id
                            and d.is_deleted = 0
                where not exists(select 1 from @map where item_id = x.item_id)
                    and isnull(x.is_deleted, 0) = 0
                group by x.item_id

        -- print '@my_drafts'
            -- сформируем куст деталей для замены
            declare @my_drafts as table(draft_id int primary key)
                insert into @my_drafts(draft_id)
                select distinct c.draft_id
                from sdocs_mfr_contents cp
                    join sdocs_mfr_contents c on c.mfr_doc_id = cp.mfr_doc_id and c.product_id = cp.product_id
                        and c.node.IsDescendantOf(cp.node) = 1
                where cp.mfr_doc_id = @doc_id
                    and cp.draft_id = @draft_id
                    and c.is_buy = 0

        -- seed
            declare @seed_id int = isnull((select max(draft_id) from mfr_drafts), 0)
        
            update x set new_draft_id = @seed_id + i.row_id
            from @map x
                join (
                    select 
                        item_id,
                        row_number() over (order by draft_id) as row_id
                    from @map
                ) i on i.item_id = x.item_id
                    
        -- delete old
            delete from mfr_drafts where draft_id in (select draft_id from @my_drafts)
            exec mfr_drafts_purge @mol_id = @mol_id, @docs = @docs

        -- print 'insert MFR_DRAFTS'
            SET IDENTITY_INSERT SDOCS_MFR_DRAFTS ON;

                insert into mfr_drafts(
                    template_id, draft_id, plan_id, mfr_doc_id, product_id, item_id, is_buy, status_id, number, d_doc, mol_id, note,
                    item_price0, opers_count, add_mol_id, main_id, prop_weight, prop_size, is_root, part_q
                    )
                select 
                    @template_id, i.new_draft_id, null, @doc_id, @product_id, x.item_id, is_buy, 0, number, d_doc, @mol_id, note,
                    item_price0, opers_count, @mol_id, main_id, prop_weight, prop_size, is_root, part_q
                from mfr_drafts x
                    join @map i on i.draft_id = x.draft_id
                where not exists(select 1 from mfr_drafts where mfr_doc_id = @doc_id and item_id = x.item_id)
            
            SET IDENTITY_INSERT SDOCS_MFR_DRAFTS OFF;

        -- print ' + DETAILS'
            declare @map_drafts as app_mapids
                insert into @map_drafts(id, new_id)
                select distinct draft_id, new_draft_id from @map

        -- print 'apply sync'
            exec mfr_draft_sync;2 @mol_id = @mol_id, @map = @map_drafts

        -- print 'recalc drafts'
            exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs

    COMMIT TRANSACTION
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        declare @err varchar(max); set @err = error_message()
        raiserror (@err, 16, 3)
    END CATCH -- TRANSACTION

    final:
        -- close log	
        exec tracer_close @tid
        if @trace = 1 exec tracer_view @tid
        return

    mbr:
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        raiserror('manual break', 16, 1)
end
GO
-- helper: copy details of drafts
create proc mfr_draft_sync;2
	@mol_id int,
	@map app_mapids readonly,
	@map_reversed app_mapids readonly,
	@parts varchar(100) = null -- указать через запятую
as
begin

	create table #realmap(source_id int index ix1, target_id int index ix2)
	
	if exists(select 1 from @map)
		insert into #realmap(source_id, target_id)
		select id, new_id from @map
	else 
		insert into #realmap(source_id, target_id)
		select new_id, id from @map_reversed

	-- MFR_DRAFTS_ITEMS
		if charindex('items', isnull(@parts, 'items')) > 0
			insert into mfr_drafts_items(
				draft_id, item_id, item_type_id, is_buy, unit_name, q_netto, q_brutto, add_mol_id, is_deleted
				)
			select 
				i.target_id, x.item_id, x.item_type_id, x.is_buy, x.unit_name, x.q_netto, x.q_brutto, @mol_id, x.is_deleted
			from mfr_drafts_items x
				join #realmap i on i.source_id = x.draft_id
			where not exists(select 1 from mfr_drafts_items where draft_id = i.target_id)

    -- MFR_DRAFTS_DOCS
		if charindex('docs', isnull(@parts, 'docs')) > 0
			insert into mfr_drafts_docs(
				draft_id, number, name, note, url, add_mol_id, is_deleted
				)
			select 
				i.target_id, number, name, note, url, @mol_id, is_deleted
			from mfr_drafts_docs x
				join #realmap i on i.source_id = x.draft_id
            where x.number != 'httpref' -- see tg_sdocs_mfr_drafts_attrs trigger

    -- MFR_DRAFTS_OPERS
		if charindex('opers', isnull(@parts, 'opers')) > 0
		begin
			EXEC SYS_SET_TRIGGERS 0

			-- MFR_DRAFTS_OPERS
				create table #map_opers(
					old_oper_id int index ix1, oper_id int, draft_id int,
					index ix2 (old_oper_id, draft_id)
					)

				insert into mfr_drafts_opers(
					draft_id, extern_id, operkey,
					reserved, number, place_id, type_id, work_type_id, name, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, is_deleted, count_executors, count_resources, is_first, is_last, is_virtual, count_workers, percent_automation
					)
					output inserted.reserved, inserted.oper_id, inserted.draft_id into #map_opers
				select 
					i.target_id, x.extern_id, x.operkey,
					x.oper_id, x.number, x.place_id, x.type_id, x.work_type_id, x.name, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.is_deleted, x.count_executors, x.count_resources, x.is_first, x.is_last, x.is_virtual, x.count_workers, x.percent_automation
				from mfr_drafts_opers x
					join #realmap i on i.source_id = x.draft_id

			-- MFR_DRAFTS_OPERS_EXECUTORS
				insert into mfr_drafts_opers_executors(
					draft_id, oper_id, post_id, duration_wk, duration_wk_id, rate_price, note, add_mol_id, is_deleted
					)
				select 
					m.draft_id, m.oper_id, x.post_id, x.duration_wk, x.duration_wk_id, x.rate_price, x.note, @mol_id, x.is_deleted
				from mfr_drafts_opers_executors x
					join #realmap i on i.source_id = x.draft_id
					join #map_opers m on m.old_oper_id = x.oper_id and m.draft_id = i.target_id

			-- MFR_DRAFTS_OPERS_RESOURCES
				insert into mfr_drafts_opers_resources(
					draft_id, oper_id, resource_id, equipment_id, loading, note, add_mol_id, is_deleted, loading_price, loading_value
					)
				select 
					m.draft_id, m.oper_id, x.resource_id, x.equipment_id, x.loading, x.note, @mol_id, x.is_deleted, x.loading_price, x.loading_value
				from mfr_drafts_opers_resources x
					join #realmap i on i.source_id = x.draft_id
					join #map_opers m on m.old_oper_id = x.oper_id and m.draft_id = i.target_id
			
			EXEC SYS_SET_TRIGGERS 1
		end
		
	-- MFR_DRAFTS_ATTRS
		insert into mfr_drafts_attrs(draft_id, attr_id, note, add_mol_id)
		select i.target_id, attr_id, note, @mol_id
		from mfr_drafts_attrs x
			join #realmap i on i.source_id = x.draft_id

	exec drop_temp_table '#realmap,#map_opers'
end
GO
