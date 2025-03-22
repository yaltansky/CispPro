if object_id('mfr_reps_materials_pays') is not null drop proc mfr_reps_materials_pays
go
-- exec mfr_reps_materials_pays 1000, -1
create proc mfr_reps_materials_pays
	@mol_id int,
    @folder_id int, -- папка заказов
    @trace bit = 0
as
begin
	set nocount on;

	-- #docs
		create table #docs(id int primary key)

        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'

	-- reglament access
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key);	insert into #subjects select distinct obj_id from @objects where obj_type = 'sbj'

    -- #result
        declare @item_group1 varchar(50) = dbo.app_registry_varchar('MfrRepMaterialGroup1Attr')

        select 
            ContentId = c.content_id,
            MfrNumber = mfr.number,
            ProductName = pr.name,
            ItemName = pr1.name,
            GroupMaterialName = g2.name,
            MaterialId = c.item_id,
            MaterialName = pr2.name,
            SupplierName = isnull(a.name, '-'),
            ManagerName = isnull(m.name, '-'),
            MaterialValue = c.item_price0 * c.q_brutto_product,
            DateIssueFrom = c.opers_to
        into #result
        from sdocs_mfr_contents c
            join sdocs_mfr_contents cp on cp.mfr_doc_id = c.mfr_doc_id and cp.product_id = c.product_id
                and cp.child_id = c.parent_id
            join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id
                join #docs d on d.id = mfr.doc_id
                join #subjects s on s.id = mfr.subject_id
            join products pr on pr.product_id = c.product_id
            join products pr1 on pr1.product_id = cp.item_id
            join products pr2 on pr2.product_id = c.item_id
                left join (
                    select product_id, name = isnull(pa.attr_value, '-')
                    from products_attrs pa
                        join (
                            select top 1 attr_id from prodmeta_attrs where code = @item_group1
                        ) a on a.attr_id = pa.attr_id
                ) g2 on g2.product_id = pr2.product_id
            left join agents a on a.agent_id = c.supplier_id
            left join mols m on m.mol_id = c.manager_id
        where c.is_buy = 1
            
            ; create index ix_material on #result(MaterialId)

    -- calc pays
        create table #result_invoices(
            MaterialId int,
            InvoiceId int,
            MilestoneName varchar(100),
            Ratio float,
            DateDiff int,
            DateLag int,
            primary key (MaterialId, MilestoneName)
            )

        insert into #result_invoices(MaterialId, InvoiceId, MilestoneName, Ratio, [DateDiff], DateLag)
        select 
            m.MaterialId, i.invoice_id, isnull(i.milestone_name, '-'), isnull(i.ratio, 1), 
            isnull(i.date_diff,0),
            isnull(i.date_lag,0)
        from (
            select distinct MaterialId from #result
            ) m
            left join (
                select 
                    imax.product_id,
                    invoice_id = imax.doc_id, 
                    milestone_name = msn.name, ms.ratio,
                    date_diff = datediff(d, inv.d_delivery, ms.d_to),
                    ms.date_lag
                from (
                    -- max doc_id
                    select sp.product_id, doc_id = max(sd.doc_id)
                    from sdocs_products sp
                        join supply_invoices sd on sd.doc_id = sp.doc_id
                        join (
                            -- max date
                            select sp.product_id, d_doc = max(sd.d_doc)
                            from sdocs_products sp
                                join supply_invoices sd on sd.doc_id = sp.doc_id
                            where sd.status_id >= 0
                            group by sp.product_id
                        ) dd on dd.product_id = sp.product_id and dd.d_doc = sd.d_doc
                    group by sp.product_id
                    ) imax
                    join sdocs inv on inv.doc_id = imax.doc_id
                    join supply_invoices_milestones ms on ms.doc_id = imax.doc_id
                        join supply_invoices_milestones_names msn on msn.milestone_id = ms.milestone_id
                where ms.ratio > 0
            ) i on i.product_id = m.MaterialId

    select *,
        DatePayPlanWeek = concat(datepart(year, DatePayPlan), '-', datepart(iso_week, DatePayPlan))
    from (
        select r.*,
            ri.MilestoneName,
            DatePayPlan = dateadd(d, ri.DateLag, dateadd(d, ri.DateDiff, r.DateIssueFrom)),
            ValuePay = r.MaterialValue * ri.Ratio
        from #result r
            join #result_invoices ri on ri.MaterialId = r.MaterialId
        ) x
    
    exec drop_temp_table '#result,#result_invoices'
end
go
