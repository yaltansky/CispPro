if object_id('objs_folder_getrefs_mfr') is not null drop proc objs_folder_getrefs_mfr
go
-- exec objs_folder_getrefs_mfr 1000, -1, 'MFC'
create proc objs_folder_getrefs_mfr
	@mol_id int,
	@folder_id int,
	@obj_type_source varchar(16) = null,
	@obj_type_target varchar(16) = null
as
begin

	set nocount on;

    -- @buffer_id
    declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
    if @folder_id = -1 set @folder_id = @buffer_id

    -- @buffer
    declare @buffer as app_pkids; insert into @buffer exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type_source

    -- clear buffer	
    delete from objs_folders_details where folder_id = @buffer_id and obj_type != @obj_type_source

    declare @maxrows int = 10000

    -- Производственные планы
        if @obj_type_source = 'mfp'
        begin            
            if @obj_type_target = 'p'            
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'p', x.product_id, @mol_id
                from sdocs_products x
                    join mfr_sdocs mfr on mfr.doc_id = x.doc_id
                        join @buffer buf on buf.id = mfr.plan_id

            else if @obj_type_target = 'mfr'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfr', x.doc_id, @mol_id
                from mfr_sdocs x
                    join @buffer buf on buf.id = x.plan_id
        end

    -- Производственные заказы
        if @obj_type_source = 'mfr'
        begin
            if @obj_type_target = 'mfc'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', x.content_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.mfr_doc_id
                where is_buy = 0

            else if @obj_type_target = 'mfm'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', x.content_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.mfr_doc_id
                where is_buy = 1
        end

    -- Тех.выписки
        else if @obj_type_source = 'mfd'
        begin
            declare @drafts as app_pkids

            if @obj_type_target = 'mfc'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', c.content_id, @mol_id
                from sdocs_mfr_drafts x
                    join @buffer buf on buf.id = x.draft_id
                    join sdocs_mfr_contents c on c.mfr_doc_id = x.mfr_doc_id and c.draft_id = x.draft_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                        and obj_id = c.content_id
                    )
            end

            else if @obj_type_target = 'mfd-all'
            begin
                insert into @drafts select id from @buffer

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfd', x.draft_id, @mol_id
                from sdocs_mfr_drafts x
                    join sdocs_mfr_drafts x2 on x2.item_id = x.item_id
                        join @drafts i on i.id = x2.draft_id
                    join sdocs sd on sd.doc_id = x.mfr_doc_id
                        join mfr_plans pl on pl.plan_id = sd.plan_id and pl.status_id = 1
            end

            else if @obj_type_target = 'mfd-unique'
            begin
                insert into @drafts select id from @buffer

                exec objs_buffer_clear @mol_id, 'mfd'

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select @buffer_id, 'mfd', max(x.draft_id), @mol_id
                from sdocs_mfr_drafts x
                    join @drafts i on i.id = x.draft_id
                group by x.item_id 
            end
        end

    -- Детали, материалы, состав изделия
        else if @obj_type_source = 'mfc'
        begin
            if @obj_type_target = 'mfr'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfr', x.mfr_doc_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfr'
                        and obj_id = x.mfr_doc_id
                    )
            end

            if @obj_type_target = 'p'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'p', x.product_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'p'
                        and obj_id = x.product_id
                    )
            end

            if @obj_type_target = 'p2'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'p', x.item_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'p'
                        and obj_id = x.item_id
                    )
            end

            else if @obj_type_target = 'mfd'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfd', x.draft_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfd'
                        and obj_id = x.draft_id
                    )

            else if @obj_type_target = 'mfc-parents'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', xc.content_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                    join sdocs_mfr_contents xc on xc.mfr_doc_id = x.mfr_doc_id and xc.product_id = x.product_id
                        and x.node.GetAncestor(1) = xc.node
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                        and obj_id = xc.content_id
                    )

            else if @obj_type_target = 'mfc-parentsall'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', xc.content_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                    join sdocs_mfr_contents xc on xc.mfr_doc_id = x.mfr_doc_id and xc.product_id = x.product_id
                        and x.node.IsDescendantOf(xc.node) = 1
                        and x.node != xc.node
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                        and obj_id = xc.content_id
                    )

            else if @obj_type_target = 'mfc-parentsonly'
            begin
                delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc2'
                update objs_folders_details set obj_type = 'mfc2' where folder_id = @buffer_id and obj_type = 'mfc'

                declare @parents table(
                    c_child_id int index ix_child, c_parent_id int, lvl int,
                    index ix_bound (c_child_id, lvl)
                    )
                    
                insert into @parents
                select c.content_id, cp.content_id, cp.node.GetLevel()
                from sdocs_mfr_contents c
                    join @buffer buf on buf.id = c.content_id
                    join sdocs_mfr_contents cp on cp.mfr_doc_id = c.mfr_doc_id and cp.product_id = c.product_id and c.node.IsDescendantOf(cp.node) = 1
                        join @buffer buf2 on buf2.id = cp.content_id
                
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', c_parent_id, @mol_id
                from @parents p
                    join (
                        select c_child_id, lvl = min(lvl)
                        from @parents
                        group by c_child_id
                    ) pp on pp.c_child_id = p.c_child_id and pp.lvl = p.lvl

                delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc2'
            end

            else if @obj_type_target = 'mfc-childs'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', xc.content_id, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                    join sdocs_mfr_contents xc on xc.mfr_doc_id = x.mfr_doc_id and xc.product_id = x.product_id
                        and xc.node.IsDescendantOf(x.node) = 1
                        and xc.node != x.node
                        and xc.has_childs = 1
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                        and obj_id = xc.content_id
                    )

            else if @obj_type_target = 'mfm'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', x.material_content_id, @mol_id
                from v_sdocs_mfr_materials x
                    join @buffer buf on buf.id = x.item_content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                        and obj_id = x.material_content_id
                    )

            else if @obj_type_target = 'mfm-parents'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', x.item_content_id, @mol_id
                from v_sdocs_mfr_materials x
                    join @buffer buf on buf.id = x.material_content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                        and obj_id = x.item_content_id
                    )

            else if @obj_type_target = 'mfm-siblings'
            begin
                exec objs_buffer_clear @mol_id, 'mfc'

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select distinct @buffer_id, 'mfc', c.content_id, 0
				from sdocs_mfr_contents c
					join (
                        select mfr_doc_id, product_id, item_id
                        from sdocs_mfr_contents c
                            join @buffer i on i.id = c.content_id
                    ) cc on cc.mfr_doc_id = c.mfr_doc_id and cc.product_id = c.product_id
						and cc.item_id = c.item_id
                where c.is_buy = 1
            end

            else if @obj_type_target = 'mfj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfj', r.job_id, @mol_id
                from sdocs_mfr_contents c
                    join @buffer buf on buf.id = c.content_id
                    join v_mfr_r_plans_jobs_items_all r on r.content_id = c.content_id
                where r.job_id is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfj'
                            and obj_id = r.job_id
                        )

            else if @obj_type_target = 'mco'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mco', x.detail_id, @mol_id
                from mfr_plans_jobs_queues x
                    join @buffer buf on buf.id = x.content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mco'
                        and obj_id = x.detail_id
                    )

            else if @obj_type_target = 'ship'
            begin
                set @obj_type_target = 'sd'
                
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, r.id_ship, @mol_id
                from mfr_r_provides r
                    join @buffer buf on buf.id = r.id_mfr
                where r.id_ship is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, r.id_ship, @mol_id
                from mfr_r_provides_archive r
                    join @buffer buf on buf.id = r.id_mfr
                where r.id_ship is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                        and obj_id = r.id_ship
                        )
            end

            else if @obj_type_target = 'mftrf'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, r.id_job, @mol_id
                from mfr_r_provides r
                    join @buffer buf on buf.id = r.id_mfr
                where r.id_job is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, r.id_job, @mol_id
                from mfr_r_provides_archive r
                    join @buffer buf on buf.id = r.id_mfr
                where r.id_job is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                        and obj_id = r.id_job
                        )
            end

            else if @obj_type_target = 'swp'
            begin
                exec objs_buffer_clear @mol_id, 'swp'

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'swp', swp.doc_id, @mol_id
                from mfr_sdocs_contents c
                    join @buffer buf on buf.id = c.content_id
                    join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id
                    join mfr_swaps_products swp on swp.mfr_number in ('ALL', mfr.number) and swp.dest_product_id = c.item_id
                        join mfr_swaps sw on sw.doc_id = swp.doc_id
                where sw.status_id >= 0
            end

            else if @obj_type_target = 'mfo'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfo', oper_id, @mol_id
                from sdocs_mfr_opers o
                    join @buffer buf on buf.id = o.content_id
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfo'
                        and obj_id = o.oper_id
                    )

            else if @obj_type_target = 'buyorder'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'buyorder', prv.id_order, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                    join mfr_r_provides prv on prv.id_mfr = x.content_id
                where prv.id_order is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'buyorder'
                        and obj_id = prv.id_order
                        )

            else if @obj_type_target = 'inv'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, prv.id_invoice, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                    join mfr_r_provides prv on prv.id_mfr = x.content_id
                where prv.id_invoice is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, prv.id_invoice, @mol_id
                from sdocs_mfr_contents x
                    join @buffer buf on buf.id = x.content_id
                    join mfr_r_provides_archive prv on prv.id_mfr = x.content_id
                where prv.id_invoice is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                        and obj_id = prv.id_invoice
                        )
            end

            else if @obj_type_target = 'invpay' 
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'invpay', x.row_id, @mol_id
                from mfr_sdocs_contents c
                    join @buffer buf on buf.id = c.content_id
                    join mfr_r_provides prv on prv.id_mfr = c.content_id
                        join supply_r_invpays_totals x on x.mfr_doc_id = prv.mfr_doc_id and x.item_id = prv.item_id and x.inv_id = prv.id_invoice

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'invpay', x.row_id, @mol_id
                from mfr_sdocs_contents c
                    join @buffer buf on buf.id = c.content_id
                    join mfr_r_provides_archive prv on prv.id_mfr = c.content_id
                        join supply_r_invpays_totals x on x.mfr_doc_id = prv.mfr_doc_id and x.item_id = prv.item_id and x.inv_id = prv.id_invoice
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'invpay' and obj_id = x.row_id
                    )
            end
        end

    -- Операции
        else if @obj_type_source = 'mfo'
        begin
            if @obj_type_target = 'mfc'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.content_id, @mol_id
                from mfr_sdocs_opers x
                    join @buffer buf on buf.id = x.oper_id
                where not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                            and obj_id = x.content_id
                        )        
            
            else if @obj_type_target = 'mfj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.plan_job_id, @mol_id
                from v_mfr_plans_jobs_details x
                    join @buffer buf on buf.id = x.oper_id
                where not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                            and obj_id = x.plan_job_id
                        )

            else if @obj_type_target = 'prj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, pt.project_id, @mol_id
                from mfr_sdocs_opers x
                    join @buffer buf on buf.id = x.oper_id
                        join projects_tasks pt on pt.task_id = x.project_task_id
                where not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfj'
                            and obj_id = pt.project_id
                        )
        end

    -- Библиотека
        else if @obj_type_source = 'mfpdm'
        begin
            if @obj_type_target = 'p'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'p', x.item_id, @mol_id
                from mfr_pdms x
                    join @buffer i on i.id = x.pdm_id
            
            else if @obj_type_target = 'childs'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfpdm', xx.pdm_id, @mol_id
                from mfr_pdm_items x
                    join @buffer i on i.id = x.pdm_id
                    join mfr_pdms xx on xx.item_id = x.item_id
                where x.is_deleted = 0;

            else if @obj_type_target = 'parents'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfpdm', xp.pdm_id, @mol_id
                from mfr_pdms x
                    join @buffer i on i.id = x.pdm_id
                    join mfr_pdm_items xp on xp.item_id = x.item_id
                where xp.is_deleted = 0;
        end

    -- Табели рабочего времени
        else if @obj_type_source = 'mfw'
        begin
            if @obj_type_target = 'mfj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'mfj', x.plan_job_id, @mol_id
                from mfr_wk_sheets_jobs x
                    join @buffer i on i.id = x.wk_sheet_id
                -- where duration_wk > 0
        end

    -- Сменные задания
        else if @obj_type_source = 'mfwd'
        begin
            if @obj_type_target = 'mfw'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.wk_sheet_id, @mol_id
                from mfr_wk_sheets_details x
                    join @buffer buf on buf.id = x.id

            else if @obj_type_target = 'mfj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.plan_job_id, @mol_id
                from mfr_wk_sheets_jobs x
                    join (
                        select distinct wd.wk_sheet_id, wd.mol_id
                        from mfr_wk_sheets_details wd
                            join @buffer buf on buf.id = wd.id
                    ) wd on wd.wk_sheet_id = x.wk_sheet_id and x.mol_id = wd.mol_id
        end

    -- Производственные задания
        else if @obj_type_source = 'mfj'
        begin
            if @obj_type_target = 'mfc'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', x.content_id, @mol_id
                from mfr_plans_jobs_details x
                    join @buffer buf on buf.id = x.plan_job_id
                where x.content_id is not null
            
            else if @obj_type_target = 'mco'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mco', x.detail_id, @mol_id
                from mfr_plans_jobs_queues x
                    join @buffer buf on buf.id = x.plan_job_id
                where not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                            and obj_id = x.detail_id
                        )

            else if @obj_type_target = 'mfw'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfw', x.wk_sheet_id, @mol_id
                from mfr_wk_sheets_jobs x
                    join @buffer buf on buf.id = x.plan_job_id
                where not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                            and obj_id = x.detail_id
                        )
        end

    -- Очередь заданий
        else if @obj_type_source = 'mco'
        begin
            if @obj_type_target = 'mco-next'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mco', nn.detail_id, @mol_id
                from mfr_plans_jobs_queues x
                    join @buffer i on i.id = x.detail_id
                    join sdocs_mfr_opers o on o.oper_id = x.oper_id
                        join mfr_plans_jobs_queues nn on nn.oper_id = o.next_id
            end

            else if @obj_type_target = 'mfc'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'MFC', x.content_id, @mol_id
                from mfr_plans_jobs_queues x
                    join @buffer i on i.id = x.detail_id
                where x.content_id is not null
            
            else if @obj_type_target = 'mfj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfj', x.plan_job_id, @mol_id
                from mfr_plans_jobs_queues x
                    join @buffer i on i.id = x.detail_id
        end

    -- Передаточные накладные
        else if @obj_type_source = 'mftrf'
        begin
            if @obj_type_target = 'mfm' 
            begin
                declare @mfr table(id_mfr int)
                    insert into @mfr select distinct id_mfr from mfr_r_provides x
                        join @buffer i on i.id = x.id_job
                    where x.id_mfr is not null

                    insert into @mfr select distinct id_mfr from mfr_r_provides_archive x
                        join @buffer i on i.id = x.id_job
                    where x.archive = 1 and x.id_mfr is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', id_mfr, @mol_id from @mfr
            end
        end

    -- Счета поставщиков
        else if @obj_type_source = 'inv'
        begin
            if @obj_type_target = 'buyorder'
            begin            
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_order, @mol_id
                from mfr_r_provides x
                    join @buffer i on i.id = x.id_invoice
                where x.id_order is not null
            end
            
            else if @obj_type_target = 'ships'
            begin            
                set @obj_type_target = 'sd'
                
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_ship, @mol_id
                from mfr_r_provides x
                    join @buffer i on i.id = x.id_invoice
                where x.id_ship is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_ship, @mol_id
                from mfr_r_provides_archive x
                    join @buffer i on i.id = x.id_invoice
                where x.id_ship is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                        and obj_id = x.id_ship
                        )
            end

            else if @obj_type_target = 'invpay'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'invpay', x.row_id, @mol_id
                from supply_r_invpays_totals x
                    join @buffer i on i.id = x.inv_id

            else if @obj_type_target = 'mfc'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_mfr, @mol_id
                from mfr_r_provides x
                    join @buffer buf on buf.id = x.id_invoice
                where x.id_mfr is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_mfr, @mol_id
                from mfr_r_provides_archive x
                    join @buffer buf on buf.id = x.id_invoice
                where x.id_mfr is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                        and obj_id = x.id_mfr
                        )
            end

            else if @obj_type_target = 'po'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'po', x.payorder_id, @mol_id
                from payorders_materials x
                    join @buffer buf on buf.id = x.invoice_id
        end

    -- Заявки на закупку
        else if @obj_type_source = 'buyorder'
        begin
            if @obj_type_target = 'mfm'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', x.id_mfr, @mol_id
                from mfr_r_provides x
                    join @buffer buf on buf.id = x.id_order
                where x.id_mfr is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'
                        and obj_id = x.id_mfr
                        )

            else if @obj_type_target = 'inv'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'inv', x.id_invoice, @mol_id
                from mfr_r_provides x
                    join @buffer buf on buf.id = x.id_order
                where x.id_invoice is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'inv'
                        and obj_id = x.id_invoice
                        )
        end

    -- Счета и оплаты
        else if @obj_type_source = 'invpay'
        begin
            if @obj_type_target = 'inv'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'inv', x.inv_id, @mol_id
                from supply_r_invpays_totals x
                    join @buffer i on i.id = x.row_id

            else if @obj_type_target = 'invpayByInvoices'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'invpay', x.row_id, @mol_id
                from supply_r_invpays_totals x
                    join supply_invoices inv on inv.doc_id = x.inv_id
                    join (
                        select distinct inv.d_doc, inv.agent_id, inv.number from supply_r_invpays_totals r
                            join supply_invoices inv on inv.doc_id = r.inv_id
                            join @buffer i on i.id = r.row_id
                        where r.inv_id is not null
                    ) xx on xx.agent_id = inv.agent_id and xx.d_doc = inv.d_doc and xx.number = inv.number
                where not exists(
                    select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = 'invpay' and obj_id = x.row_id
                    )
            end

            else if @obj_type_target = 'po'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'po', x.payorder_id, @mol_id
                from payorders_materials x
                where exists(
                        select 1 from supply_r_invpays_totals inv
                            join @buffer i on i.id = inv.row_id
                        where inv_id = x.invoice_id and mfr_doc_id = x.mfr_doc_id and item_id = x.item_id
                    )
        end

    -- Замены материалов
        else if @obj_type_source = 'swp'
        begin
            if @obj_type_target = 'mfm'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfc', c.content_id, @mol_id
                from sdocs_mfr_contents c
                    join (
                        select 
                            mfr.doc_id as mfr_doc_id,
                            sp.dest_product_id as item_id
                        from mfr_swaps_products sp
                            join @buffer buf on buf.id = sp.doc_id
                            join mfr_sdocs mfr on mfr.number = sp.mfr_number
                    ) x on x.mfr_doc_id = c.mfr_doc_id and x.item_id = c.item_id
                where c.is_buy = 1 and c.is_swap = 1
            end
        end

    -- Товарные документы
        else if @obj_type_source = 'sd'
        begin
            if @obj_type_target = 'mfm'
            begin
                set @obj_type_target = 'mfc'
                
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_mfr, @mol_id
                from mfr_r_provides x
                    join @buffer buf on buf.id = x.id_ship
                where x.id_mfr is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_mfr, @mol_id
                from mfr_r_provides_archive x
                    join @buffer buf on buf.id = x.id_ship
                where x.id_mfr is not null
                    and not exists(
                            select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                                and obj_id = x.id_mfr
                            )
            end
            
            else if @obj_type_target = 'inv'
            begin
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_invoice, @mol_id
                from mfr_r_provides x
                    join @buffer buf on buf.id = x.id_order
                where x.id_invoice is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_invoice, @mol_id
                from mfr_r_provides_archive x
                    join @buffer buf on buf.id = x.id_order
                where x.id_invoice is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                            and obj_id = x.id_invoice
                        )
            end

            else if @obj_type_target = 'mfm_by_ord'
            begin
                set @obj_type_target = 'mfc'
                
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_mfr, @mol_id
                from mfr_r_provides x
                    join @buffer buf on buf.id = x.id_order
                where x.id_mfr is not null

                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, @obj_type_target, x.id_mfr, @mol_id
                from mfr_r_provides_archive x
                    join @buffer buf on buf.id = x.id_order
                where x.id_mfr is not null
                    and not exists(
                        select 1 from objs_folders_details where folder_id = @buffer_id and obj_type = @obj_type_target
                            and obj_id = x.id_mfr
                        )
            end
        end
end
go
