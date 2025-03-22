if object_id('mfr_swaps_check') is not null drop proc mfr_swaps_check
go
create proc mfr_swaps_check
	@mol_id int,
	@queue_id uniqueidentifier = null
as
begin

  set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid), @tid_msg varchar(max)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	-- #swchk_swaps
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
        create table #swchk_swaps(id int primary key)

		if @queue_id is not null
		begin
			insert into #swchk_swaps select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'swp'
		end
		else
			insert into #swchk_swaps select id from dbo.objs_buffer(@mol_id, 'swp')

        create table #swchk_errors(doc_id int, detail_id int, errors varchar(max),
            index ix_join(doc_id, detail_id)
            )

    -- каскадные замены (M1 --> M2, M2 --> M3)
        insert into #swchk_errors(doc_id, detail_id, errors)
        select sp.doc_id, sp.detail_id, 'каскадные замены (M1 --> M2, M2 --> M3)'
        from sdocs_products sp
            join mfr_swaps sw on sw.doc_id = sp.doc_id
            join (
                select distinct sp.mfr_number, sp.product_id, sp.dest_product_id
                from sdocs_products sp
                    join #swchk_swaps i on i.id = sp.doc_id
            ) sp2 on sp2.mfr_number = sp.mfr_number
                and sp2.product_id = sp.dest_product_id
                and sp2.dest_product_id not in (sp.product_id, sp.dest_product_id)
        where sw.status_id > 0

    -- обратные замены (M1 --> M2, M2 --> M1)
        insert into #swchk_errors(doc_id, detail_id, errors)
        select sp.doc_id, sp.detail_id, 'обратные замены (M1 --> M2, M2 --> M1)'
        from sdocs_products sp
            join mfr_swaps sw on sw.doc_id = sp.doc_id
            join (
                select distinct sp.mfr_number, sp.product_id, sp.dest_product_id
                from sdocs_products sp
                    join #swchk_swaps i on i.id = sp.doc_id
            ) sp2 on sp2.mfr_number = sp.mfr_number
                and sp2.product_id = sp.dest_product_id
                and sp2.dest_product_id = sp.product_id
        where sw.status_id > 0

    -- повторные замены (M1 --> M2 в одном или нескольких документах)
        insert into #swchk_errors(doc_id, detail_id, errors)
        select sp.doc_id, sp.detail_id, 'повторные замены (M1 --> M2 в одном или нескольких документах)'
        from sdocs_products sp
            join mfr_swaps sw on sw.doc_id = sp.doc_id
            join (
                select sp.mfr_number, sp.product_id, sp.dest_product_id
                from sdocs_products sp
                    join mfr_swaps sw on sw.doc_id = sp.doc_id
                    join (
                        select distinct sp.mfr_number, sp.product_id, sp.dest_product_id
                        from sdocs_products sp
                            join #swchk_swaps i on i.id = sp.doc_id
                    ) sp2 on sp2.mfr_number = sp.mfr_number
                        and sp2.product_id = sp.product_id
                        and sp2.dest_product_id = sp.dest_product_id
                group by sp.mfr_number, sp.product_id, sp.dest_product_id
                having count(*) > 1
            ) sp2 on sp2.mfr_number = sp.mfr_number
                and sp2.product_id = sp.product_id
                and sp2.dest_product_id = sp.dest_product_id
        where sw.status_id > 0

    -- лишние замены (в заказе нет M1)
        insert into #swchk_errors(doc_id, detail_id, errors)
        select sp.doc_id, sp.detail_id, 'лишние замены (в заказе нет M1)'
        from sdocs_products sp
            join mfr_swaps sw on sw.doc_id = sp.doc_id
            join #swchk_swaps i on i.id = sp.doc_id
                join mfr_sdocs mfr on mfr.number = sp.mfr_number
        where sw.status_id > 0
            and not exists(
                select 1 from mfr_drafts_items di
                    join mfr_drafts d on d.draft_id = di.draft_id
                where d.is_deleted = 0
                    and isnull(di.is_deleted,0) = 0
                    and di.item_id = sp.product_id
                )

    -- изменение нормы (M1 → M1) 
        insert into #swchk_errors(doc_id, detail_id, errors)
        select sp.doc_id, sp.detail_id, 'изменение нормы (M1 → M1) '
        from sdocs_products sp
            join mfr_swaps sw on sw.doc_id = sp.doc_id
            join #swchk_swaps i on i.id = sp.doc_id
        where sw.status_id > 0
            and sp.product_id = sp.dest_product_id

    -- buffer
        exec objs_buffer_clear 1000, 'swp'
        insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
        select distinct @buffer_id, 'swp', doc_id, @mol_id from #swchk_errors

    -- mark errors
        update x set errors = null
        from sdocs_products x
            join (select distinct doc_id from #swchk_errors) e on e.doc_id = x.doc_id
            
        update x set errors = e.errors
        from sdocs_products x
            join #swchk_errors e on e.doc_id = x.doc_id and e.detail_id = x.detail_id

end
go
