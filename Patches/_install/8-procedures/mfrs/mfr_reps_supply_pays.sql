if object_id('mfr_reps_supply_pays') is not null drop proc mfr_reps_supply_pays
go
-- exec mfr_reps_supply_pays 1000
create proc mfr_reps_supply_pays
	@mol_id int,
	@d_doc date = null,
	@folder_id int = null
as
begin
	set nocount on;

	create table #objs(id int primary key)
	create table #findocs(id int primary key)
	declare @filter_findocs bit, @filter_invoices bit, @filter_rows bit
	
	if @folder_id is not null
	begin
		insert into #objs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'FD' -- оплаты
		if exists(select 1 from #objs) 
            set @filter_findocs = 1
		else begin
            insert into #objs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'INV' -- счета
		    if exists(select 1 from #objs) begin
			    set @filter_invoices = 1
                insert into #findocs select distinct findoc_id from supply_r_invpays
                    where findoc_id in (
                        select distinct findoc_id from supply_r_invpays
                        where inv_id in ((select id from #objs))
                        )
                        and findoc_id is not null
            end
            else begin
                insert into #objs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'INVPAY' -- строки журнала "Счета и оплаты"
                if exists(select 1 from #objs) 
			        set @filter_rows = 1
            end
		end
	end

    declare @attr_group1 int = (select top 1 attr_id from prodmeta_attrs where code = dbo.app_registry_varchar('MfrRepMaterialGroup1Attr'))
    declare @attr_group2 int = (select top 1 attr_id from prodmeta_attrs where code = dbo.app_registry_varchar('MfrRepMaterialGroup2Attr'))

	select
		x.*,
        ITEM_GROUP1_NAME = ISNULL(G1.ATTR_VALUE, '-'),
        ITEM_GROUP2_NAME = ISNULL(G2.ATTR_VALUE, '-'),
		ROW_HID = CONCAT('#', X.ROW_ID),
		MFR_DOC_HID = CONCAT('#', X.MFR_DOC_ID),
		INV_HID = CONCAT('#', X.INV_ID)
	from v_supply_r_invpays x
        left join products_attrs g1 on g1.attr_id = @attr_group1 and g1.product_id = x.item_id
        left join products_attrs g2 on g2.attr_id = @attr_group2 and g2.product_id = x.item_id
	where (@d_doc is null or x.inv_d_plan <= @d_doc)
		and (@filter_findocs is null or x.findoc_id in (select id from #objs))
        and (@filter_invoices is null or (
            x.inv_id in (select id from #objs)
            or (x.findoc_id in (select id from #findocs) and x.inv_id is null)
        ))
		and (@filter_rows is null or exists(
			select 1 from supply_r_invpays_totals t
				join #objs i on i.id = t.row_id
			where inv_id = x.inv_id
				and inv_milestone_id = x.inv_milestone_id
				and isnull(plan_id,0) = isnull(x.plan_id,0)
				and mfr_doc_id = x.mfr_doc_id
				and item_id = x.item_id
		))
end
GO
