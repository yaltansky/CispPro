if object_id('payorders_reps_list_materials') is not null drop proc payorders_reps_list_materials
go
-- exec payorders_reps_list_materials 1000, 96225
create proc payorders_reps_list_materials
	@mol_id int,
	@folder_id int,
    @trace bit = 0
as
begin

	set nocount on;	

	declare @folders table(folder_id int primary key)
	declare @folder_name varchar(100) = (select name from objs_folders where folder_id = @folder_id)
	
	-- простой реестр
        if exists(
            select 1
            from objs_folders f
                join objs_folders_details fd on fd.folder_id = f.folder_id and fd.obj_type = 'PO'
                    join payorders o on o.payorder_id = fd.obj_id
            where f.parent_id = @folder_id
            )
            insert into @folders select @folder_id
	
	-- сводный реестр
        else begin

            declare @folder hierarchyid, @keyword varchar(50)
                select @folder = node, @keyword = keyword from objs_folders where folder_id = @folder_id

            insert into @folders 
                select distinct folder_id from objs_folders 
                where keyword = @keyword
                    and node.IsDescendantOf(@folder) = 1
        end

    -- reglament access
        declare @objects as app_objects; insert into @objects exec payorders_reglament @mol_id = @mol_id
        declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
        declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
        if exists(select 1 from @budgets where id <> -1)
        begin
            delete from @subjects
            insert into @subjects select subject_id from subjects where subject_id > 0
        end

    -- #orders
        select
            subject_name = s.short_name,
            branch_name = isnull(br.name, ''),
            account_name = '-',
            period_name = dbo.date2month(o.d_add),
            d_doc = o.d_add,
            subfolder_name = f2.name,
            agent_name = agents.name,
            agent_inn = agents.inn,
            path_name = isnull(o.pays_path, '-'),
            project_name = '-',
            budget_name = '-',
            article_name = '-',		
            base_name = o.number,
            inv.dogovor_number,
            mfr_doc_id = mfr.doc_id,
            mfr_number = mfr.number,
            mfr_acc_register = isnull(acc.name, '-'),
            product_name = cast(null as varchar(max)),
            item_name = prod.name,
            note = isnull(concat(o.note, ' /r:', o.payorder_id, '/'), ''),
            od.nds_ratio,
            om.value_ccy,
            od.payorder_id,
            project_id = 0,
            budget_id = 0
        into #orders 
        from payorders o
            left join subjects s on s.subject_id = o.subject_id
            left join branches br on br.branch_id = o.branch_id
            join objs_folders_details fd on fd.obj_id = o.payorder_id
                join objs_folders f2 on f2.folder_id = fd.folder_id
                    join objs_folders fp on (fp.folder_id = f2.parent_id or fp.folder_id = f2.folder_id)
            join payorders_materials om on om.payorder_id = o.payorder_id
                join supply_invoices inv on inv.doc_id = om.invoice_id
                left join mfr_sdocs mfr on mfr.doc_id = om.mfr_doc_id
                join products prod on prod.product_id = om.item_id
                left join accounts_registers acc on acc.acc_register_id = mfr.acc_register_id
            join (
                select payorder_id, nds_ratio = max(nds_ratio)
                from payorders_details
                where is_deleted = 0
                group by payorder_id
            )od on od.payorder_id = o.payorder_id
            left join agents on agents.agent_id = o.recipient_id
        where 
            -- reglament access
            (
            o.mol_id = @mol_id
            or o.subject_id in (select id from @subjects)
            )
            and fp.folder_id in (select folder_id from @folders)
            and f2.is_deleted = 0

        delete from #orders where value_ccy is null

    -- product_name
        update x set product_name = concat(
            product_name, 
            case when product_name is not null then ',' end,
            p.name
            )
        from #orders x
            join sdocs_products sp on sp.doc_id = x.mfr_doc_id
                join products p on p.product_id = sp.product_id

if @trace = 1 begin
    select sum(value_ccy) from #orders
    return
end

    -- select & drop
        select * from #orders
end
GO
