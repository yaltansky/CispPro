if object_id('mfr_reps_materials_use') is not null drop proc mfr_reps_materials_use
go
-- exec mfr_reps_materials_use 1000, -1
create proc mfr_reps_materials_use
	@mol_id int,
    @folder_id int -- папка заказов
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
            MfrNumber = mfr.number,
            ProductName = pr.name,
            ItemName = pr1.name,
            GroupMaterialName = g2.name,
            MaterialName = pr2.name,
            SupplierName = isnull(a.name, '-'),
            ManagerName = isnull(m.name, '-'),
            UnitName = c.unit_name,
            QNettoProduct = c.q_netto_product,
            QBruttoProduct = c.q_brutto_product,
            QWaste = cast(null as float),
            Price = c.item_price0,
            VNettoProduct = cast(null as float),
            VBruttoProduct = c.q_brutto_product * c.item_price0,
            RatioNettoBrutto = cast(null as float),
            DateFromPlan = c.opers_from_plan
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

    -- calc
        declare @QNettoProduct float
        update #result set 
            @QNettoProduct = isnull(QNettoProduct, QBruttoProduct),
            QNettoProduct = @QNettoProduct,
            QWaste = QBruttoProduct - QNettoProduct,
            VNettoProduct = @QNettoProduct * Price,
            RatioNettoBrutto = (@QNettoProduct * Price) / nullif(VBruttoProduct, 0)

    select * from #result
    drop table #result
end
GO
