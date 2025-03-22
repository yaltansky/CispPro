if object_id('mfr_reps_items_coops') is not null drop proc mfr_reps_items_coops
go
-- exec mfr_reps_items_coops 1000, @folder_id = -1
create proc mfr_reps_items_coops
	@mol_id int,
	@folder_id int,
	@context varchar(20) = 'docs' -- docs, contents
as
begin
	set nocount on;
	set transaction isolation level read uncommitted;

    -- @docs
        declare @docs as app_pkids
        declare @contents as app_pkids

    -- buffer/folder
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
        if @context = 'contents'
            insert into @contents exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfc'

        else if @context = 'docs'
        begin
            set @context = 'contents'

            insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'

            insert into @contents
            select content_id from sdocs_mfr_contents where mfr_doc_id in (select id from @docs)
        end

    -- #opers
        select 
            x.oper_id, do.place_id, c.mfr_doc_id, c.product_id, c.item_id,
            d_doc = cast(x.d_from_plan as date),
            oper_name = x.name,
            coop_item_id = dr.item_id,
            x.status_id,
            quantity = dr.quantity * c.q_brutto_product,
            plan_cost = (dr.quantity * c.q_brutto_product) * dr.sum_price
        into #opers
        from sdocs_mfr_opers x
            join sdocs_mfr_contents c on c.content_id = x.content_id
                join mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = x.number
                    left join mfr_drafts_opers_coops dr on dr.draft_id = do.draft_id and dr.oper_id = do.oper_id
        where c.content_id in (select id from @contents)
            and x.work_type_id = 3 -- кооперация

            create unique index ix_join_opers on #opers(oper_id)

    -- select
        select 
            PlaceName = pl.full_name,
            MfrNumber = mfr.number,
            ProductName = p1.name,
            ItemName = p2.name,
            OperName = r.oper_name,
            CoopName = isnull(p3.name, '-'),
            DateFromPlan = r.d_doc,
            OperStatusName = st.name,
            Quantity = r.quantity,
            PlanCost = r.plan_cost,
            FactCost = cast(null as float)
        from #opers r
            join mfr_places pl on pl.place_id = r.place_id
            join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
            join products p1 on p1.product_id = r.product_id
            join products p2 on p2.product_id = r.item_id
            left join products p3 on p3.product_id = r.coop_item_id
            left join mfr_items_statuses st on st.status_id = r.status_id

        exec drop_temp_table '#opers'
end
GO
