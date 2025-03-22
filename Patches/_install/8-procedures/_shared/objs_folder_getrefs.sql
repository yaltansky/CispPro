if object_id('objs_folder_getrefs') is not null drop proc objs_folder_getrefs
go
-- exec objs_folder_getrefs 1000, -1, 'MFC'
create proc objs_folder_getrefs
	@mol_id int,
	@folder_id int,
	@obj_type_source varchar(16) = null,
	@obj_type_target varchar(16) = null
as
begin

	set nocount on;

    -- show meta data (as menu items)
        if @obj_type_target is null
        begin        
            select 
                OBJ_TYPE = X.TO_OBJ_TYPE,
                OBJ_NAME = ISNULL(X.TO_OBJ_NAME, OT.NAME),
                OBJ_URL = ISNULL(X.URL, OT.URL),
                REFS_COUNT = NULL -- unused
            from objs_meta_refs x
                left join objs_types ot on ot.type = x.to_obj_type
            where x.from_obj_type = @obj_type_source

            return
        end

    -- prepare
        exec objs_folders_restore @folder_id = @folder_id

        -- @buffer_id
        declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
        if @folder_id = -1 set @folder_id = @buffer_id

        -- @buffer
        declare @buffer as app_pkids; insert into @buffer exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type_source
        
        -- clear buffer	
        delete from objs_folders_details where folder_id = @buffer_id and obj_type != @obj_type_source

        declare @maxrows int = 10000

    -- Контрагенты
        if @obj_type_source = 'a' 
        begin

            if @obj_type_target = 'fd'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'fd', x.findoc_id, 0
                from findocs# x
                    join @buffer i on i.id = x.agent_id
            else if @obj_type_target = 'dl'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'dl', x.deal_id, 0
                from deals x
                    join @buffer i on i.id in (x.customer_id, x.consumer_id)
            else if @obj_type_target = 'mfr'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'mfr', x.doc_id, 0
                from mfr_sdocs x
                    join @buffer i on i.id = x.agent_id
            else if @obj_type_target = 'doc'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'doc', x.document_id, 0
                from documents x
                    join @buffer i on i.id = x.agent_id
        end
    
    -- Заявки на оплату
        if @obj_type_source = 'po' 
        begin
            if @obj_type_target = 'fd'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select @buffer_id, 'fd', x.findoc_id, @mol_id
                from (
                    select distinct pp.findoc_id
                    from payorders_pays pp
                        join @buffer i on i.id = pp.payorder_id
                    ) x

            else if @obj_type_target = 'bdg'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'bdg', x.budget_id, @mol_id
                from payorders_details x
                    join @buffer i on i.id = x.payorder_id		
                    left join deals d on d.budget_id = x.budget_id
                where d.deal_id is null -- кроме бюджетов сделок
                    and x.budget_id is not null

            else if @obj_type_target = 'dl'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'dl', d.deal_id, @mol_id
                from payorders_details x
                    join @buffer i on i.id = x.payorder_id
                    join deals d on d.budget_id = x.budget_id
        
            else if @obj_type_target = 'prj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'prj', p.project_id, @mol_id
                from payorders_details x
                    join @buffer i on i.id = x.payorder_id
                    join budgets b on b.budget_id = x.budget_id
                        join projects p on p.project_id = b.project_id and p.type_id not in (3)

            else if @obj_type_target = 'inv'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'inv', x.invoice_id, @mol_id
                from payorders_materials x
                    join @buffer i on i.id = x.payorder_id
        end

    -- Оплаты
        else if @obj_type_source = 'fd' 
        begin
            if @obj_type_target = 'po'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select top(@maxrows) @buffer_id, 'po', x.payorder_id, @mol_id
                from (
                    select distinct pp.payorder_id
                    from payorders_pays pp
                        join @buffer i on i.id = pp.findoc_id
                    ) x

            else if @obj_type_target = 'inv'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'inv', x.invoice_id, @mol_id
                from findocs_invoices x
                    join @buffer i on i.id = x.findoc_id

            else if @obj_type_target = 'bdg'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'bdg', x.budget_id, @mol_id
                from findocs# x
                    join @buffer i on i.id = x.findoc_id
                    left join deals d on d.budget_id = x.budget_id
                where x.budget_id is not null

            else if @obj_type_target = 'a'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'a', x.agent_id, 0
                from findocs# x
                    join @buffer i on i.id = x.findoc_id
                where x.agent_id is not null

            else if @obj_type_target = 'dl'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'dl', d.deal_id, @mol_id
                from findocs# x
                    join @buffer i on i.id = x.findoc_id
                    join deals d on d.budget_id = x.budget_id
        
            else if @obj_type_target = 'prj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'prj', p.project_id, @mol_id
                from findocs# x
                    join @buffer i on i.id = x.findoc_id
                    join budgets b on b.budget_id = x.budget_id
                        join projects p on p.project_id = b.project_id and p.type_id not in (3)
        end

    -- Счета (частично)
        else if @obj_type_source = 'inv'
        begin
            if @obj_type_target = 'fd'
            begin            
                exec objs_buffer_clear @mol_id, 'fd'
                
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'fd', x.findoc_id, @mol_id
                from findocs_invoices x
                    join @buffer i on i.id = x.invoice_id
                
                return
            end
        end

    -- Бюджеты
        else if @obj_type_source = 'bdg'
        begin
            if @obj_type_target = 'po'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'po', x.payorder_id, @mol_id
                from payorders_details x
                    join @buffer i on i.id = x.budget_id

            else if @obj_type_target = 'fd'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'fd', x.findoc_id, @mol_id
                from findocs# x
                    join @buffer i on i.id = x.budget_id

            else if @obj_type_target = 'prj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'prj', p.project_id, @mol_id
                from budgets x
                    join @buffer i on i.id = x.budget_id
                    join projects p on p.project_id = x.project_id and p.type_id not in (3)
        end

    -- Проекты
        else if @obj_type_source = 'prj'
        begin
            if @obj_type_target = 'po'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'po', x.payorder_id, @mol_id
                from payorders_details x
                    join budgets b on b.budget_id = x.budget_id
                        join @buffer i on i.id = b.project_id

            else if @obj_type_target = 'fd'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'fd', x.findoc_id, @mol_id
                from findocs# x
                    join budgets b on b.budget_id = x.budget_id
                        join @buffer i on i.id = b.project_id

            else if @obj_type_target = 'bdg'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'bdg', p.project_id, @mol_id
                from budgets x
                    join @buffer i on i.id = x.project_id
                    join projects p on p.project_id = x.project_id and p.type_id not in (3)

            else if @obj_type_target = 'dl'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'dl', d.deal_id, @mol_id
                from projects_tasks x
                    join @buffer i on i.id = x.project_id
                    join deals d on d.deal_id = x.ref_project_id
        end

    -- Сделки
        else if @obj_type_source = 'dl'
        begin
            if @obj_type_target = 'po'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'po', x.payorder_id, @mol_id
                from payorders_details x
                    join deals d on d.budget_id = x.budget_id
                        join @buffer i on i.id = d.deal_id

            else if @obj_type_target = 'fd'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct top(@maxrows) @buffer_id, 'fd', x.findoc_id, @mol_id
                from findocs# x
                    join deals d on d.budget_id = x.budget_id
                        join @buffer i on i.id = d.deal_id

            else if @obj_type_target = 'prj'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'prj', x.project_id, @mol_id
                from projects_tasks x			
                    join deals d on d.deal_id = x.ref_project_id
                        join @buffer i on i.id = d.deal_id

            if @obj_type_target = 'a'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'a', d.customer_id, @mol_id
                from deals d
                    join @buffer i on i.id = d.deal_id
                where d.customer_id is not null
        end
    
    -- Товарные документы
        else if @obj_type_source = 'sd'
        begin
            if @obj_type_target = 'a'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'a', d.agent_id, @mol_id
                from sdocs d
                    join @buffer i on i.id = d.doc_id
                where d.agent_id is not null
            
            else if @obj_type_target = 'inv'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select distinct @buffer_id, 'inv', d.id_invoice, @mol_id
                from mfr_r_provides d
                    join @buffer i on i.id = d.id_ship
                where d.id_invoice is not null
        end
   
        if @obj_type_target = 'P'
          and @obj_type_source in ('SD', 'INV', 'MFTRF', 'SWP')
        begin
            exec objs_buffer_clear @mol_id, 'P'

            insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
            select distinct @buffer_id, 'P', d.product_id, @mol_id
            from (
                select d.product_id from sdocs_products d
                    join @buffer i on i.id = d.doc_id
                where d.product_id is not null
                union 
                select d.dest_product_id from sdocs_products d
                    join @buffer i on i.id = d.doc_id
                where d.dest_product_id is not null
            ) d
        end

    -- Производственные заказы
        if @obj_type_source like 'mf%'
            or @obj_type_source in ('mco', 'inv', 'invpay', 'buyorder', 'swp', 'sd')
        begin
            delete @buffer
            exec objs_folder_getrefs_mfr
                @mol_id = @mol_id,
                @folder_id = @folder_id,
                @obj_type_source = @obj_type_source,
                @obj_type_target = @obj_type_target
        end
end
go
