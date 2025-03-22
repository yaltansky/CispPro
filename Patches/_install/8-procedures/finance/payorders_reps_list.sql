if object_id('payorders_reps_list') is not null drop proc payorders_reps_list
go
create proc payorders_reps_list
	@mol_id int,
	@folder_id int
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
            project_name = isnull(projects.name, '-'),
            budget_name = budgets.name,
            article_name = art.name,		
            base_name = o.number,
            inv.dogovor_number,
            note = isnull(concat(o.note, ' /r:', o.payorder_id, '/'), ''),
            value_ccy = od.value_ccy,
            od.nds_ratio,
            od.payorder_id,
            budgets.project_id,
            budgets.budget_id
        into #orders 
        from payorders o
            left join subjects s on s.subject_id = o.subject_id
            left join branches br on br.branch_id = o.branch_id
            join objs_folders_details fd on fd.obj_id = o.payorder_id
                join objs_folders f2 on f2.folder_id = fd.folder_id
                    join objs_folders fp on (fp.folder_id = f2.parent_id or fp.folder_id = f2.folder_id)
            join payorders_details od on od.payorder_id = o.payorder_id
                left join (
                    select payorder_id, invoice_id = max(invoice_id)
                    from payorders_materials
                    group by payorder_id
                ) om on om.payorder_id = o.payorder_id
                    left join supply_invoices inv on inv.doc_id = om.invoice_id
                join budgets on budgets.budget_id = od.budget_id
                    left join projects on projects.project_id = budgets.project_id and projects.type_id = 1
                left join bdr_articles art on art.article_id = od.article_id
            left join agents on agents.agent_id = o.recipient_id
        where 
            -- reglament access
            (
            o.mol_id = @mol_id
            or o.subject_id in (select id from @subjects)
            or od.budget_id in (select id from @budgets)
            )
            and fp.folder_id in (select folder_id from @folders)
            and f2.is_deleted = 0
            and od.is_deleted = 0

        delete from #orders where value_ccy is null

    -- select & drop
        select * from #orders
        drop table #orders
end
GO
