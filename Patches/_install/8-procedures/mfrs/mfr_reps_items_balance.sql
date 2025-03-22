if object_id('mfr_reps_items_balance') is not null drop proc mfr_reps_items_balance
go
-- exec mfr_reps_items_balance 1000, @folder_id = -1
create proc mfr_reps_items_balance
	@mol_id int,
	@folder_id int = null,
    @d_from date = null,
	@d_to date = null,
	@search varchar(max) = null
as
begin
	set nocount on;

	exec mfr_items_balance_calc -- sync MFR_R_ITEMS_BALANCE

	set @d_from = isnull(@d_from, '2000-01-01')
	set @d_to = isnull(@d_to, dbo.today())
	set @search = '%' + replace(@search, ' ', '%') + '%'

    create table #docs(id int primary key)
    if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
    if @folder_id is null
        insert into #docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id between 0 and 99
    else
        insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'

	-- tables
		declare @turn table(
			place_id int,
			place_from_id int,
			mfr_doc_id int,
			item_id int,
			content_id int,
			doc_type varchar(20),
			doc_id int,
			job_id int,
			d_doc date,
			unit_name varchar(20),
			q_start float,
			q_input float,
			q_output float,
			q_end float,
			index ix_group (place_id, mfr_doc_id, item_id)
		)	

	-- оборотная ведомость
		-- входящий остаток
			insert into @turn(place_id, mfr_doc_id, item_id, d_doc, doc_type, q_start, unit_name)
			select
				r.place_id,
				r.mfr_doc_id,
				r.item_id,				
				d_doc = @d_from,
				number = 'ВхОстаток',
				sum(r.quantity),
				max(r.unit_name)
			from mfr_r_items_balance r
				join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
                    join #docs i on i.id = mfr.doc_id
				join products p on p.product_id = r.item_id
			where r.d_doc < @d_from
				and (@search is null 
					or (mfr.number like @search or p.name like @search)
					)
			group by r.place_id, r.mfr_doc_id, r.item_id

		-- обороты
			insert into @turn(place_id, place_from_id, mfr_doc_id, item_id, content_id, doc_type, doc_id, d_doc, q_input, q_output, unit_name)
			select
				r.place_id,
				r.place_from_id,
				r.mfr_doc_id,
				r.item_id,
				r.content_id,
				case 
					when r.doc_id is not null then 'Накладная'
					when r.job_id is not null then 'СЗ'
					else '-'
				end,				
				isnull(r.doc_id, r.job_id),
				r.d_doc,
				case when r.quantity > 0 then r.quantity end,
				case when r.quantity < 0 then -r.quantity end,
				r.unit_name
			from mfr_r_items_balance r
				join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
                    join #docs i on i.id = mfr.doc_id
				join products p on p.product_id = r.item_id
			where r.d_doc between @d_from and @d_to
				and (@search is null 
					or (mfr.number like @search or p.name like @search)
					)

		-- исходящий остаток
			insert into @turn(place_id, mfr_doc_id, item_id, d_doc, doc_type, q_end, unit_name)
			select
				r.place_id,
				r.mfr_doc_id,
				r.item_id,				
				d_doc = @d_from,
				number = 'ИсхОстаток',		
				sum(isnull(r.q_start,0) + isnull(r.q_input,0) - isnull(r.q_output,0)),
				max(r.unit_name)
			from @turn r
			group by r.place_id, r.mfr_doc_id, r.item_id

	-- select
		select 
			PLACE_NAME = PL.FULL_NAME,
			MFR_NUMBER = MFR.NUMBER,
			ITEM_GROUP_NAME = PG1.NAME,
			ITEM_NAME = P.NAME,		
			X.DOC_TYPE,
			X.D_DOC,
			UNIT_NAME = CASE WHEN UK.KOEF IS NOT NULL THEN U.NAME ELSE X.UNIT_NAME END,
			Q_START = X.Q_START * ISNULL(UK.KOEF,1),
			Q_INPUT = X.Q_INPUT * ISNULL(UK.KOEF,1),
			Q_OUTPUT = X.Q_OUTPUT * ISNULL(UK.KOEF,1),
			Q_END = X.Q_END * ISNULL(UK.KOEF,1),
			DOC_HID = CONCAT('#', X.DOC_ID),
			CONTENT_HID = CONCAT('#', X.CONTENT_ID)
		from @turn x
			join mfr_places pl on pl.place_id = x.place_id
			join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id
			join products p on p.product_id = x.item_id
				left join products_units u on u.unit_id = p.unit_id
				left join products_ukoefs uk on uk.product_id = p.product_id and uk.unit_from = x.unit_name and uk.unit_to = u.name
			left join v_products_groups pg1 on pg1.product_id = x.item_id
		where abs(isnull(x.q_start,0)) > 0.001
			or abs(isnull(x.q_input,0)) > 0.001
			or abs(isnull(x.q_output,0)) > 0.001
			or abs(isnull(x.q_end,0)) > 0.001

end
go
