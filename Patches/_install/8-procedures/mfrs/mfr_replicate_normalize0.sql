if object_id('mfr_replicate_normalize0') is not null drop proc mfr_replicate_normalize0
go
create proc mfr_replicate_normalize0
	@docs app_pkids readonly
as
begin

	set nocount on;

	declare @today date = dbo.today()
	declare @nz_docs app_pkids
	create table #nz_docs(id int primary key)
	
	-- Нормализация статуса тех. выписок
        update mfr_drafts set status_id = 0 where status_id is null

    -- Удалить удалённые операции
        delete from mfr_pdm_opers where is_deleted = 1
        delete from mfr_drafts_opers where is_deleted = 1

	-- Нет состава изделия
		-- #nz_docs
			insert into #nz_docs select doc_id from mfr_sdocs mfr
				join @docs i on i.id = mfr.doc_id
			where plan_status_id = 1 and status_id >= 0
				and not exists(select 1 from mfr_drafts where mfr_doc_id = mfr.doc_id)

        if exists(select 1 from #nz_docs)
        begin
            -- mfr_drafts
                declare @map table(draft_id int primary key, mfr_doc_id int)

                insert into mfr_drafts(mfr_doc_id, product_id, item_id, is_buy, work_type_1, d_doc, number, status_id, note, is_root, is_product)
                output inserted.draft_id, inserted.mfr_doc_id into @map
                select sp.doc_id, sp.product_id, sp.product_id, 0, 1, sd.d_doc, '-', 10, 'авто-создание', 1, 1
                from sdocs_products sp
                    join sdocs sd on sd.doc_id = sp.doc_id
                    join #nz_docs i on i.id = sp.doc_id
            
                update d set product_id = sp.product_id
                from mfr_drafts d
                    join sdocs_products sp on sp.doc_id = d.mfr_doc_id
                where d.product_id != sp.product_id

            -- mfr_drafts_opers
                insert into mfr_drafts_opers(draft_id, place_id, number, name, duration, duration_id)
                select draft_id, 
                    case when db_name() = 'CISP_SEZ' then 503 end,
                    1, 'Контроль', 1, 2
                from @map

            -- calc contents
                delete from @nz_docs;
                insert into @nz_docs select doc_id from mfr_sdocs mfr 
                    join @docs i on i.id = mfr.doc_id
                where plan_status_id = 1 and status_id >= 0
                    and exists(select 1 from mfr_drafts where mfr_doc_id = mfr.doc_id)
                    and not exists(select 1 from sdocs_mfr_contents where mfr_doc_id = mfr.doc_id)
                
                exec mfr_drafts_calc 1000, @docs = @nz_docs
        end
        
	-- Нет операций у ключевой детали
		delete from #nz_docs;
		insert into #nz_docs select doc_id from mfr_sdocs mfr 
			join @docs i on i.id = mfr.doc_id
		where plan_status_id = 1 and status_id >= 0
			and exists(
				select 1 from mfr_drafts d
				where mfr_doc_id = mfr.doc_id and is_product = 1
					and not exists(select 1 from mfr_drafts_opers where draft_id = d.draft_id)
				)
		
		insert into mfr_drafts_opers(draft_id, number, name, duration, duration_id)
		select draft_id, 1, 'Контроль', 1, 2
		from mfr_drafts d
			join #nz_docs i on i.id = d.mfr_doc_id
		where d.is_product = 1
			and not exists(select 1 from mfr_drafts_opers where draft_id = d.draft_id)

		delete from @nz_docs; insert into @nz_docs select id from #nz_docs
		exec mfr_drafts_calc 1000, @docs = @nz_docs

	-- Переделы "Готовая продукция"
		declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%готовая продукция%')

		-- milestone
		insert into sdocs_mfr_milestones(doc_id, product_id, attr_id, ratio, ratio_value)
		select mfr.doc_id, sp.product_id, @attr_product, 1, sp.value_work
		from sdocs_products sp
			join mfr_sdocs mfr on mfr.doc_id = sp.doc_id
				join @docs i on i.id = mfr.doc_id
		where not exists(select 1 from sdocs_mfr_milestones where doc_id = mfr.doc_id)

		-- #opers_product
		create table #opers_product(doc_id int, oper_id int primary key)
		insert into #opers_product(doc_id, oper_id)
		select x.doc_id, max(o.oper_id)
		from mfr_sdocs x
			join @docs i on i.id = x.doc_id
			join sdocs_mfr_contents c on c.mfr_doc_id = x.doc_id
				join mfr_drafts d on d.draft_id = c.draft_id and d.is_product = 1
				join sdocs_mfr_opers o on o.content_id = c.content_id and o.milestone_id is null
		where plan_status_id = 1
			and not exists(
				select 1 from sdocs_mfr_opers where mfr_doc_id = x.doc_id and milestone_id = 30
				)
		group by x.doc_id

		EXEC SYS_SET_TRIGGERS 0
			update x set milestone_id = @attr_product
			from sdocs_mfr_opers x
				join #opers_product op on op.oper_id = x.oper_id
		EXEC SYS_SET_TRIGGERS 1

	-- progress = 1
	EXEC SYS_SET_TRIGGERS 0
		declare @d_to_fact datetime
		update x set 
			status_id = 100, fact_q = plan_q, 
			@d_to_fact = coalesce(d_to_plan, d_to_predict, d_to),
			d_to_fact = case when @d_to_fact > @today then @today else @d_to_fact end
		from sdocs_mfr_opers x
			join @docs i on i.id = x.mfr_doc_id
		where progress = 1 and (fact_q is null or d_to_fact is null)
			and work_type_id != 1 -- закупки
			and plan_q > 0
			and coalesce(d_to_plan, d_to_predict, d_to) is not null
	EXEC SYS_SET_TRIGGERS 1

	-- changed product_id
		update d set product_id = sp.product_id
		from mfr_drafts d
			join @docs i on i.id = d.mfr_doc_id
			join (
				select doc_id, product_id = max(product_id)
				from sdocs_products
				group by doc_id
				having count(*) = 1
			) sp on sp.doc_id = d.mfr_doc_id
		where d.product_id != sp.product_id

    -- read prices
		delete from #nz_docs;
		insert into #nz_docs select id from @docs

        declare @sum_price float

        update x set
            @sum_price = sd.price * coalesce(uk.koef, dbo.product_ukoef(u1.name, u2.name), 1),
            sum_price = @sum_price,
            sum_value = quantity * @sum_price
        from mfr_drafts_opers_coops x
            join mfr_drafts d on d.draft_id = x.draft_id
                join #nz_docs i on i.id = d.mfr_doc_id
            join (
                select sp.product_id, sp.unit_id, sp.price
                from sdocs_products sp
                    join (
                        select sp.product_id, last_doc_id = max(sd.doc_id)
                        from sdocs_products sp
                            join sdocs sd on sd.doc_id = sp.doc_id and sd.type_id = 8
                        group by sp.product_id
                    ) smax on smax.last_doc_id = sp.doc_id
            ) sd on sd.product_id = x.item_id
            join products_units u1 on u1.unit_id = sd.unit_id
            join products_units u2 on u2.unit_id = x.unit_id
            left join products_ukoefs uk on uk.product_id = x.item_id and uk.unit_from = u1.name and uk.unit_to = u2.name
        where isnull(x.sum_price, 0) = 0

	exec drop_temp_table '#opers_product'

end
GO
