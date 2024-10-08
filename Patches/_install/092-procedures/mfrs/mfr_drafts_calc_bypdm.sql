if object_id('mfr_drafts_calc_bypdm') is not null drop proc mfr_drafts_calc_bypdm
go
create proc [mfr_drafts_calc_bypdm]
	@mol_id int,
	@start_draft_id int
as
begin

    set nocount on;

	declare	@mfr_doc_id int, @product_id int, @start_pdm_id int
		select 
			@mfr_doc_id = mfr_doc_id,
			@product_id = product_id,
			@start_pdm_id = pdm_id
		from mfr_drafts where draft_id = @start_draft_id

	-- tables
		create table #drafts(draft_id int primary key)

	-- apply pdm to drafts
		declare @drafts app_pkids
		insert into @drafts select @start_draft_id
		exec mfr_drafts_calc_bypdm;2 @mol_id = @mol_id, @drafts = @drafts, @enforce = 1

	-- loop
		declare @level int = 0
		declare @maxlevel int = 100

		while @level < @maxlevel -- страховка: не более N уровней
		begin
			insert into #drafts(draft_id)
			select distinct dd.draft_id from mfr_drafts_items di
				join mfr_drafts d on d.draft_id = di.draft_id
				join mfr_drafts dd on dd.mfr_doc_id = d.mfr_doc_id and dd.product_id = d.product_id
					and dd.item_id = di.item_id
			where d.draft_id in (select id from @drafts)

			if @@rowcount = 0 break -- добрались до нижнего уровня иерархии?
			set @level = @level + 1

			delete from @drafts; insert into @drafts select draft_id from #drafts
			exec mfr_drafts_calc_bypdm;2 @mol_id = @mol_id, @drafts = @drafts
			truncate table #drafts
		end
end
GO
-- helper: apply pdm
create proc [mfr_drafts_calc_bypdm];2
	@mol_id int,
	@drafts app_pkids readonly,
	@enforce bit = 0
as
begin

	-- #bypdm_drafts2
		create table #bypdm_drafts2(id int primary key, route_number int default(1))
			insert into #bypdm_drafts2(id) select draft_id 
			from mfr_drafts d
				join @drafts dd on dd.id = d.draft_id
			where @enforce = 1
				or (not exists(select 1 from mfr_drafts_items where draft_id = d.draft_id)
					and d.pdm_id is not null
					)

		if not exists(select 1 from #bypdm_drafts2) return -- nothing todo

		update x set route_number = pdm.route_number
		from #bypdm_drafts2 x
			join mfr_drafts_pdm pdm on pdm.draft_id = x.id 
		where pdm.route_number is not null

	-- purge
		delete from mfr_drafts_items where draft_id in (select id from #bypdm_drafts2)
		delete from mfr_drafts_opers where draft_id in (select id from #bypdm_drafts2)
		delete from mfr_drafts_opers_executors where draft_id in (select id from #bypdm_drafts2)
		delete from mfr_drafts_opers_resources where draft_id in (select id from #bypdm_drafts2)

	-- mfr_drafts_items
		insert into mfr_drafts_items(draft_id, item_id, item_type_id, numbers, place_id, is_buy, unit_name, q_netto, q_brutto)
		select d.draft_id, pi.item_id, pi.item_type_id, pi.numpos, pi.place_id, pi.is_buy, pi.unit_name, pi.q_netto, pi.q_brutto
		from mfr_pdm_items pi
			join mfr_drafts d on d.pdm_id = pi.pdm_id
				join #bypdm_drafts2 dd on dd.id = d.draft_id
			join products p on p.product_id = pi.item_id
		where 
			-- options
			(
				pi.pdm_option_id is null
				or exists(
					select 1 from mfr_drafts_pdm where draft_id = d.draft_id
						and pdm_option_id = pi.pdm_option_id
					)
			)
			-- analogs
			and (
				(pi.parent_id is null and pi.has_childs = 0)
				or exists(
					select 1 from mfr_drafts_pdm where draft_id = d.draft_id
						and analog_id = pi.id
					)
			)

		order by d.draft_id, right(concat('0000000000', pi.numpos), 10) , p.name

	-- mfr_drafts_opers
		create table #map_opers(old_oper_id int index ix_oper, oper_id int, draft_id int)

		EXEC SYS_SET_TRIGGERS 0
			insert into mfr_drafts_opers(
				draft_id, reserved, 
				number, place_id, type_id, name, predecessors, duration, duration_id, duration_wk, duration_wk_id, add_mol_id, count_executors, count_resources, is_first, is_last, count_workers, operkey
				)
				output inserted.reserved, inserted.oper_id, inserted.draft_id into #map_opers
			select 
				d.draft_id, x.oper_id, 
				x.number, x.place_id, x.type_id, x.name, x.predecessors, x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, @mol_id, x.count_executors, x.count_resources, x.is_first, x.is_last, x.count_workers, x.operkey
			from mfr_pdm_opers x
				join mfr_drafts d on d.pdm_id = x.pdm_id
					join #bypdm_drafts2 dd on dd.id = d.draft_id and dd.route_number = x.variant_number
		EXEC SYS_SET_TRIGGERS 1

	-- mfr_drafts_opers_executors
		insert into mfr_drafts_opers_executors(
			draft_id, oper_id, post_id, duration_wk, duration_wk_id, note, add_mol_id
			)
		select 
			m.draft_id, m.oper_id, x.post_id, x.duration_wk, x.duration_wk_id, x.note, @mol_id
		from mfr_pdm_opers_executors x		
			join #map_opers m on m.old_oper_id = x.oper_id

	-- mfr_drafts_opers_resources
		insert into mfr_drafts_opers_resources(
			draft_id, oper_id, resource_id, loading, note, add_mol_id, loading_price, loading_value
			)
		select 
			m.draft_id, m.oper_id, x.resource_id, x.loading, x.note, @mol_id, x.loading_price, x.loading_value
		from mfr_pdm_opers_resources x
			join #map_opers m on m.old_oper_id = x.oper_id

	-- auto-append drafts
		declare @today date = dbo.today()

		EXEC SYS_SET_TRIGGERS 0
			insert into mfr_drafts(mfr_doc_id, product_id, item_id, unit_name, pdm_id, is_buy, d_doc, number, status_id, add_mol_id)
			select distinct d.mfr_doc_id, d.product_id, di.item_id, di.unit_name, pdm.pdm_id, 0, @today, isnull(pdm.number, '-'), 0, @mol_id
			from mfr_drafts_items di
				join mfr_drafts d on d.draft_id = di.draft_id
					join #bypdm_drafts2 dd on dd.id = d.draft_id
				left join mfr_pdms pdm on pdm.item_id = di.item_id and pdm.is_default = 1
			where not exists(
					select 1 from mfr_drafts where mfr_doc_id = d.mfr_doc_id and product_id = d.product_id
						and item_id = di.item_id
					)
		EXEC SYS_SET_TRIGGERS 1
	drop table #map_opers
end
GO
