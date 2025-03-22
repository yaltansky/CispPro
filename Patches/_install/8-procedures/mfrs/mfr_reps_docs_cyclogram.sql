if object_id('mfr_reps_docs_cyclogram') is not null drop proc mfr_reps_docs_cyclogram
go
-- exec mfr_reps_docs_cyclogram 1000, @folder_id = -1
create proc mfr_reps_docs_cyclogram
	@mol_id int,	
	@folder_id int = null, -- буфер/папка заказов
	@context varchar(50) = null -- docs
as
begin
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- params
		declare @docs as app_pkids
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
        insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
			
    -- select
		select
			PlanName = pln.number,
			MfrNumber = sd.number,
			ProductName = p.name,
			PlaceName = isnull(pl.full_name, '-'),
			ItemName = pi.name,
			ItemStatus = isnull(st1.name, '-'),
			ItemQuantity = x.q_brutto_product,
			OperName = o.name,
			OperStatus = isnull(st2.name, '-'),
			OperDateFrom = cast(o.d_from as date),
			OperDateTo = cast(o.d_to as date)
		from sdocs_mfr_contents x
			join sdocs sd on sd.doc_id = x.mfr_doc_id
				join mfr_plans pln on pln.plan_id = sd.plan_id
                join @docs i on i.id = sd.doc_id
            join sdocs_mfr_opers o on o.content_id = x.content_id
			    left join mfr_places pl on pl.place_id = o.place_id
			left join products p on p.product_id = x.product_id
			left join products pi on pi.product_id = x.item_id
			left join mfr_items_statuses st1 on st1.status_id = x.status_id
			left join mfr_items_statuses st2 on st2.status_id = o.status_id

	final:
		exec drop_temp_table '#contents,#opers,#result'
end
GO
