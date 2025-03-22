if object_id('mfr_reps_nzp') is not null drop proc mfr_reps_nzp
go
-- exec mfr_reps_nzp 1000
create proc mfr_reps_nzp
	@mol_id int,
	@folder_id int = null, -- folder with orders
	@recalc bit = 0
as
begin

	set nocount on;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

	declare @docs as app_pkids
	if @folder_id is null
		insert into @docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id between 0 and 99
	else
		insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
	
	if @recalc = 1
	begin
		declare @subject_id int = (select top 1 subject_id from sdocs where doc_id in (select id from @docs))

		if dbo.isinrole_byobjs(@mol_id, 'Mfr.Admin,Mfr.Admin.Materials', 'SBJ', @subject_id) = 0
		begin
			raiserror('У Вас нет доступа к пересчёту регистра НЗП в данном субъекте учёта (роли Mfr.Admin,Mfr.Admin.Materials).', 16, 1)
			return
		end

		exec mfr_items_unfinished_calc @mol_id = @mol_id
	end

	create table #unfinished(
		mfr_doc_id int index ix_mfr_doc,
		product_id int,
		content_id int index ix_content,
		status_id int,
		item_id int,
		place_id int,
		mfr_materials_v float,
		mfr_hours float,
		materials_v float,
		fact_hours float
		)

	insert into #unfinished(
		mfr_doc_id, product_id, content_id, status_id, item_id, place_id, materials_v, fact_hours
		)
	select
		mfr_doc_id, product_id, content_id, status_id, item_id, place_id, materials_v, fact_hours
	from mfr_r_items_unfinished x
		join @docs i on i.id = x.mfr_doc_id

	declare @mfr_docs app_pkids
	insert into @mfr_docs select distinct mfr_doc_id from #unfinished

	-- Суммарная стоимость материалов по заказам
	insert into #unfinished(mfr_doc_id, product_id, place_id, mfr_materials_v)
	select c.mfr_doc_id, product_id, -100, sum(item_value0)
	from sdocs_mfr_contents c
		join @mfr_docs i on i.id = c.mfr_doc_id
	where is_buy = 1		
	group by mfr_doc_id, product_id

	-- Суммарная трудоёмкость по заказам
	insert into #unfinished(mfr_doc_id, place_id, product_id, mfr_hours)
	select c.mfr_doc_id, -100, c.product_id, sum(duration_wk)
	from sdocs_mfr_opers o
		join sdocs_mfr_contents c on c.content_id = o.content_id
			join @mfr_docs i on i.id = c.mfr_doc_id
	group by c.mfr_doc_id, c.product_id

	select
		MFR_NUMBER = MFR.NUMBER,
		PRODUCT_NAME = P1.NAME,
		ITEM_NAME = ISNULL(P2.NAME, '-'),
		STATUS_NAME = ISNULL(ST.NAME, '-'),
		PLACE_NAME = 
			CASE
				WHEN X.PLACE_ID = -100 THEN '(ЗАКАЗЫ)'
				ELSE ISNULL(PL.FULL_NAME, '-')
			END,
		X.MFR_MATERIALS_V,
		X.MFR_HOURS,
		X.MATERIALS_V,
		X.FACT_HOURS,
		CONTENT_HID = CONCAT('#', X.CONTENT_ID)
	from #unfinished x
		join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id
		join products p1 on p1.product_id = x.product_id
		left join products p2 on p2.product_id = x.item_id
		left join mfr_items_statuses st on st.status_id = x.status_id
		left join mfr_places pl on pl.place_id = x.place_id

end
go
