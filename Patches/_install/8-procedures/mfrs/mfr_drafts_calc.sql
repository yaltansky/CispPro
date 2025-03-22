if object_id('mfr_drafts_calc') is not null drop proc mfr_drafts_calc
go
-- exec mfr_drafts_calc @mol_id = 1000, @doc_id = 609513, @trace = 1
create proc mfr_drafts_calc
	@mol_id int,
	@plan_id int = null,
	@doc_id int = null,
	@docs app_pkids readonly,
	@drafts app_pkids readonly,
	@product_id int = null,
    @queue_id uniqueidentifier = null,
	@trace bit = 0
as
begin
	set nocount on;

	-- params
		DECLARE @MAXLEVEL INT = 100
		declare @use_transfer_opers bit = isnull(cast((select dbo.app_registry_value('MfrUseTransferOpers')) as bit), 1)
		set @trace = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), @trace)

		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @mol_id=', @mol_id,
			' @doc_id=', @doc_id,
            ' @queue_id=', @queue_id
			)
		exec tracer_log @tid, @tid_msg

	exec tracer_log @tid, 'prepare'
		declare @docs2 as app_pkids
		
		if @plan_id is not null
			insert into @docs2 select doc_id from mfr_sdocs where plan_id = @plan_id
		else if @doc_id is not null 
			insert into @docs2 select @doc_id
		else if @queue_id is not null begin
            select @mol_id = mol_id from queues where queue_id = @queue_id
            insert into @docs2 select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfr'
        end
        else
			insert into @docs2 select id from @docs

		if not exists(select 1 from @docs2)
		begin
			return -- nothing todo
		end

		create table #dc_docs(id int primary key)
		insert into #dc_docs select id from @docs2

		-- purge
		exec mfr_drafts_purge @mol_id = @mol_id, @docs = @docs2

		if exists(select 1 from @drafts)
		begin
			-- calc only opers
			exec mfr_drafts_calc;2 @drafts = @drafts, @use_transfer_opers = @use_transfer_opers, @tid = @tid
			goto final
		end

    exec tracer_log @tid, 'normalize'
		update d set product_id = sp.product_id
		from mfr_drafts d
			join #dc_docs i on i.id = d.mfr_doc_id
			join (
				select sp.doc_id, product_id = max(product_id)
				from sdocs_products sp
                    join mfr_sdocs mfr on mfr.doc_id = sp.doc_id
				group by sp.doc_id
				having count(*) = 1
			) sp on sp.doc_id = d.mfr_doc_id
		where d.product_id != sp.product_id

        update x set duration = 1, duration_id = 2
        from mfr_drafts_opers x
            join mfr_drafts d on d.draft_id = x.draft_id
                join #dc_docs i on i.id = d.mfr_doc_id
        where x.duration is null

	exec tracer_log @tid, 'calc is_root'

        -- clear root
            update x set is_root = 0
            from mfr_drafts x
                join #dc_docs i on i.id = x.mfr_doc_id
            where x.is_root = 1
                and exists(
                    select 1 
                    from mfr_drafts_items di
                        join mfr_drafts d on d.draft_id = di.draft_id
                    where x.mfr_doc_id = d.mfr_doc_id
                        and di.item_id = x.item_id
                        and d.is_deleted = 0
                        and isnull(di.is_deleted,0) = 0
                    )

        -- auto-root
            declare @checkdocs as app_pkids
                insert into @checkdocs select distinct x.mfr_doc_id from mfr_drafts x with(nolock)
                    join sdocs sd with(nolock) on sd.doc_id = x.mfr_doc_id
                        join #dc_docs i on i.id = sd.doc_id
                where not exists(select 1 from mfr_drafts where mfr_doc_id = x.mfr_doc_id and is_root = 1 and is_deleted = 0)

            if exists(select 1 from @checkdocs)
            begin
                update x set is_root = 1
                from mfr_drafts x
                where x.mfr_doc_id in (select id from @checkdocs)
                    -- есть детализация
                    and exists(select 1 from mfr_drafts_items where draft_id = x.draft_id and is_deleted = 0)
                    -- не содержится в детализации любых деталей
                    and not exists(
                        select 1 
                        from mfr_drafts_items di
                            join mfr_drafts d on d.draft_id = di.draft_id
                        where x.mfr_doc_id = d.mfr_doc_id
                            and di.item_id = x.item_id
                            and d.is_deleted = 0
                            and isnull(di.is_deleted,0) = 0
                        )

                -- -- авто-создание корневого чертежа из спецификации заказа
                -- if not exists(
                --     select 1 from mfr_drafts
                --     where mfr_doc_id in (select id from @checkdocs)
                --         and product_id is not null
                --         and is_root = 1
                --     )
                -- begin
                --     insert into mfr_drafts(mfr_doc_id, product_id, is_root, item_id, is_buy, d_doc, status_id, note, add_date, add_mol_id)
                --     select 
                --         doc_id, product_id, 1, product_id, 0, 
                --         dbo.today(),
                --         0, 'сформировано автоматически (готовое изделие)',
                --         getdate(), @mol_id
                --     from sdocs_products x
                --     where doc_id in (select id from @checkdocs)
                --         and not exists(
                --             select 1 from mfr_drafts where mfr_doc_id = x.doc_id
                --                 and product_id = x.product_id
                --                 and is_root = 1
                --             )
                -- end
            end

		update x set product_id = xx.product_id
		from mfr_drafts x
			join #dc_docs i on i.id = x.mfr_doc_id
			join sdocs_products xx on xx.doc_id = x.mfr_doc_id
		where x.product_id is null

	exec tracer_log @tid, 'calc is_product'

		delete from @checkdocs
		insert into @checkdocs select id from #dc_docs i
		where not exists(
			select 1 from mfr_drafts where mfr_doc_id = i.id and is_product = 1 and is_deleted = 0
			)

		if exists(select 1 from @checkdocs)
			and not exists(
				select 1 from mfr_drafts d
					join @checkdocs i on i.id = d.mfr_doc_id
				where d.is_deleted = 0 and is_product = 1
				)
		begin
			-- autocalc is_product based on is_root
			update x set is_product = 1
			from mfr_drafts x
				join @checkdocs chk on chk.id = x.mfr_doc_id
				join (
					select mfr_doc_id from mfr_drafts
					where is_buy = 0 and is_root = 1 and is_deleted = 0
					group by mfr_doc_id
					having count(*) = 1 
				) xx on xx.mfr_doc_id = x.mfr_doc_id
			where is_root = 1
		end

		-- update source, status
		update dd set 
			source_id = 1, -- кисп
			status_id = 10 -- принят
		from mfr_drafts d
			join #dc_docs i on i.id = d.mfr_doc_id
			join mfr_drafts_items di on di.draft_id = d.draft_id
					join mfr_drafts dd on dd.mfr_doc_id = d.mfr_doc_id and dd.item_id = di.item_id
		where isnull(d.is_deleted,0) = 0
			and d.source_id = 1
			and isnull(dd.is_deleted,0) = 1

	exec tracer_log @tid, 'compile content'

        create table #dc_mfr_defects(
			mfr_doc_id int,
			item_id int,
            q_defect float,
            primary key clustered (mfr_doc_id, item_id)
            )
            insert into #dc_mfr_defects(mfr_doc_id, item_id, q_defect)
            select mfr.doc_id, sp.product_id, sum(sp.quantity)
            from sdocs_products sp
                join sdocs_defects def on def.doc_id = sp.doc_id
                join mfr_sdocs mfr on mfr.number = sp.mfr_number and mfr.status_id >= 0
                    join #dc_docs i on i.id = mfr.doc_id
            where def.status_id >= 0
            group by mfr.doc_id, sp.product_id
        declare @has_defects bit = case when exists(select 1 from #dc_mfr_defects) then 1 else 0 end

		create table #dc_mfr_drafts(
			draft_id int index ix_draft,
			mfr_doc_id int,
			d_doc date,
			item_id int,
			unit_name varchar(20),
			item_price0 float,
			is_buy bit,
			index ix_item1(mfr_doc_id, draft_id),
			index ix_item2(mfr_doc_id, item_id)
			)
			insert into #dc_mfr_drafts(mfr_doc_id, item_id, is_buy, draft_id, d_doc, item_price0)
			select mfr.doc_id, x.item_id, x.is_buy, min(x.draft_id), min(x.d_doc), min(x.item_price0)
			from mfr_drafts x
				join mfr_sdocs mfr on isnull(mfr.part_parent_id, mfr.doc_id) = x.mfr_doc_id
			where mfr.doc_id in (select id from #dc_docs)
                and (@product_id is null or x.product_id = @product_id)
				and x.is_deleted = 0
            group by mfr.doc_id, x.item_id, x.is_buy

		create table #dc_contents(
			content_id int index ix_content,
			extern_id varchar(64) index ix_extern,
			draft_id int,
			is_new bit,
			is_swap bit,
			--
			d_doc date,
			child_id int identity primary key,
			parent_id int,
			parent_item_id int,
			has_childs bit,
			node hierarchyid,
			level_id int,
			--
			mfr_doc_id int, product_id int,
			--
			place_id int,
			item_type_id int,
			is_buy bit,
			item_id int,
            swapped_item_id int,
            swap_id int,
			name varchar(500),
			unit_name varchar(20),
			--
			q_netto_product float,
			q_brutto_product float,
			item_price0 decimal(18,2),
			--
			index ix_tree (level_id, mfr_doc_id, product_id, item_id),
			index ix_item (mfr_doc_id, product_id, item_id),
			)

        -- add level "0"
            insert into #dc_contents(
                draft_id, item_id, d_doc, level_id, mfr_doc_id, product_id, item_type_id, is_buy, unit_name, q_netto_product, q_brutto_product
                )
            select
                x.draft_id, x.item_id, x.d_doc, 0, x.mfr_doc_id, sp.product_id, 1, x.is_buy, isnull(u.name, 'шт'), sp.quantity, sp.quantity
            from mfr_drafts x
                join sdocs_products sp on sp.doc_id = x.mfr_doc_id and sp.product_id = x.product_id
                    left join products_units u on u.unit_id = sp.unit_id
            where x.mfr_doc_id in (select id from #dc_docs)
                and (@product_id is null or x.product_id = @product_id)
                and x.is_root = 1
                and x.is_buy = 0

		declare @level int = 0

		while @level < @maxlevel -- страховка: не более N уровней
		begin
            -- append childs
                insert into #dc_contents(
                    mfr_doc_id, product_id, 
                    draft_id, item_id,
                    d_doc,
                    level_id, parent_id, parent_item_id,
                    place_id, item_type_id, is_buy,
                    unit_name, q_netto_product, q_brutto_product,
                    item_price0
                    )
                select 
                    d.mfr_doc_id, parent.product_id,
                    ddi.draft_id, di.item_id,
                    case
                        when isnull(ddi.is_buy, di.is_buy) = 1 then di.add_date
                        else d.d_doc
                    end,
                    @level + 1, parent.child_id, parent.item_id,
                    di.place_id, di.item_type_id, isnull(ddi.is_buy, di.is_buy),
                    di.unit_name, 
                    parent.q_netto_product * di.q_netto,
                    parent.q_brutto_product * di.q_brutto, 
                    ddi.item_price0 / isnull(uk.koef, 1)
                from mfr_drafts_items as di
                    join #dc_mfr_drafts d on d.draft_id = di.draft_id
                        join #dc_contents as parent on
                                parent.level_id = @level
                            and parent.mfr_doc_id = d.mfr_doc_id
                            and parent.item_id = d.item_id
                    left join #dc_mfr_drafts ddi on ddi.mfr_doc_id = d.mfr_doc_id and ddi.item_id = di.item_id
                    left join products_ukoefs uk on uk.product_id = di.item_id and uk.unit_from = ddi.unit_name and uk.unit_to = di.unit_name
                where di.is_deleted = 0
                    and parent.is_buy = 0
                    and parent.q_brutto_product * di.q_brutto > 0
                order by 
                    parent.child_id, di.item_id, di.add_date, di.id

                if @@rowcount = 0 break -- добрались до нижнего уровня иерархии?
                set @level = @level + 1

            -- apply defects
                if @has_defects = 1 and exists(
                    select 1 from #dc_contents c
                        join #dc_mfr_defects d on d.mfr_doc_id = c.mfr_doc_id and d.item_id = c.item_id
                    where c.level_id = @level
                    )
                begin
                    update c set 
                        q_netto_product = q_netto_product + q_defect,
                        q_brutto_product = q_brutto_product + q_defect
                    from #dc_contents c
                        join #dc_mfr_defects d on d.mfr_doc_id = c.mfr_doc_id and d.item_id = c.item_id
                        join (
                            select mfr_doc_id, item_id, min_child_id = min(child_id)
                            from #dc_contents
                            where level_id = @level
                            group by mfr_doc_id, item_id
                        ) cc on cc.min_child_id = c.child_id
                    where c.level_id = @level

                    delete d from #dc_mfr_defects d
                        join #dc_contents c on d.mfr_doc_id = c.mfr_doc_id and d.item_id = c.item_id
                    where c.level_id = @level
                end
		end

		exec drop_temp_table '#dc_mfr_drafts,#dc_mfr_defects'
	
    exec tracer_log @tid, 'apply swaps'
		exec mfr_drafts_calc;10 @tid = @tid
	
    exec tracer_log @tid, 'build tree.node'
		update c set name = p.name
		from #dc_contents c
			join products p on p.product_id = c.item_id

			update x set 
				extern_id = concat(x.mfr_doc_id, '.', x.product_id, '.', x.parent_item_id, '#', c.parent_item_number, '.', x.item_id)
			from #dc_contents x
				join (
					select mfr_doc_id, product_id, parent_id,
						parent_item_number = row_number() over (partition by mfr_doc_id, product_id, parent_item_id order by parent_id)
					from (
						select distinct mfr_doc_id, product_id, parent_item_id, parent_id
						from #dc_contents
						) cc
				) c on c.mfr_doc_id = x.mfr_doc_id 
					and c.product_id = x.product_id
					and isnull(c.parent_id,0) = isnull(x.parent_id,0)

			if exists(select 1 from #dc_contents group by extern_id having count(*) > 1)
				update x set extern_id = dups.extern_id
				from #dc_contents x
					join (
						select
							child_id,
							extern_id = concat(xx.extern_id, '(', row_number() over (partition by mfr_doc_id, product_id, item_id order by child_id), ')')
						from #dc_contents xx
							join (
								select extern_id from #dc_contents group by extern_id having count(*) > 1
							) dups on dups.extern_id = xx.extern_id
					) dups on dups.child_id = x.child_id

		exec tracer_log @tid, 'build tree', @level = 1
			update x
			set has_childs =	
					case
						when exists(select 1 from #dc_contents where mfr_doc_id = x.mfr_doc_id and product_id = x.product_id and parent_id = x.child_id) then 1
						else 0
					end
			from #dc_contents x

			begin
				create table #dc_children(
					mfr_doc_id int, product_id int, node_id int, parent_id int, num int,
					primary key (node_id)
					)
					insert #dc_children (mfr_doc_id, product_id, node_id, parent_id, num)
					select mfr_doc_id, product_id, child_id, parent_id,  
						row_number() over (partition by mfr_doc_id, product_id, parent_id order by mfr_doc_id, product_id, has_childs desc, name)
					from #dc_contents

				create table #dc_nodes(
					mfr_doc_id int, product_id int, node_id int, node hierarchyid
					primary key (mfr_doc_id, product_id, node_id)
					)

				;with paths(mfr_doc_id, product_id, node_id, node)
				as (  
					select mfr_doc_id, product_id, node_id, cast(concat('/', c.num, '/') as hierarchyid) as node
					from #dc_children c
					where parent_id is null

					union all   
					select c.mfr_doc_id, c.product_id, c.node_id, cast(concat(p.node.ToString(), c.num, '/') as hierarchyid)
					from #dc_children as c
						join paths as p on p.mfr_doc_id = c.mfr_doc_id
							and p.product_id = c.product_id
							and p.node_id = c.parent_id
					)  
					insert into #dc_nodes(mfr_doc_id, product_id, node_id, node) select mfr_doc_id, product_id, node_id, node from paths
						
				update x
				set node = n.node
				from #dc_contents x
					join #dc_nodes as n on n.node_id = x.child_id

				exec drop_temp_table '#dc_children,#dc_nodes'
			end -- hierarchyid

	BEGIN TRY
	BEGIN TRANSACTION
		EXEC SYS_SET_TRIGGERS 0
		-- insert contents
			exec tracer_log @tid, 'sdocs_mfr_contents'

            exec tracer_log @tid, '-- get content_id'
			update x set content_id = c.content_id
			from #dc_contents x
				join sdocs_mfr_contents c on c.mfr_doc_id = x.mfr_doc_id 
					and c.product_id = x.product_id
					and c.extern_id = x.extern_id

			declare @seed_id int = isnull((select max(content_id) from sdocs_mfr_contents), 0)

            exec tracer_log @tid, '-- seed'
			update x
			set content_id = @seed_id + xx.id, is_new = 1
			from #dc_contents x
				join (
					select row_number() over (order by node) as id, extern_id
					from #dc_contents
				) xx on xx.extern_id = x.extern_id
			where x.content_id is null

			exec tracer_log @tid, '-- save olds'
			select * into #old_contents from sdocs_mfr_contents where mfr_doc_id in (select id from #dc_docs)
			;create unique index ix_old_contents on #old_contents(content_id)

			exec tracer_log @tid, '-- DELETE SDOCS_MFR_CONTENTS'
			delete from sdocs_mfr_contents where mfr_doc_id in (select id from #dc_docs)
                and (@product_id is null or product_id = @product_id)

			exec tracer_log @tid, '-- INSERT SDOCS_MFR_CONTENTS'
			SET IDENTITY_INSERT SDOCS_MFR_CONTENTS ON;

			insert into sdocs_mfr_contents(
				PLAN_ID, MFR_DOC_ID, PRODUCT_ID, CONTENT_ID, EXTERN_ID, -- key fields
				draft_id, d_doc, place_id, item_id, swapped_item_id, swap_id, item_type_id, is_buy, is_swap, name,
				supplier_id, manager_id,
				unit_name, q_netto_product, q_brutto_product, q_provided, q_provided_max,
				item_price0, item_value0,
				parent_id, child_id, node, has_childs, level_id,
				opers_from, opers_to, opers_from_plan, opers_to_plan, opers_from_ploper, opers_to_ploper, opers_from_predict, opers_to_predict, opers_days,
				d_after, d_before,
				duration_buffer, duration_buffer_predict,
				status_id, is_deleted,
				is_manual_progress,
				cancel_reason_id,
				cancel_note,
				talk_id
				)
			select
				H.PLAN_ID, H.DOC_ID, c.PRODUCT_ID, c.CONTENT_ID, c.EXTERN_ID,
				c.draft_id, c.d_doc, c.place_id, c.item_id, c.swapped_item_id, c.swap_id, c.item_type_id, c.is_buy, c.is_swap, c.name,
				old.supplier_id, old.manager_id,
				c.unit_name, c.q_netto_product, c.q_brutto_product, old.q_provided, old.q_provided_max,
				c.item_price0, (c.item_price0 * c.q_brutto_product),
				c.parent_id, c.child_id, c.node, c.has_childs, c.level_id,
				old.opers_from, old.opers_to, old.opers_from_plan, old.opers_to_plan, old.opers_from_ploper, old.opers_to_ploper, old.opers_from_predict, old.opers_to_predict, old.opers_days,
				old.d_after, old.d_before,
				old.duration_buffer, old.duration_buffer_predict,
				isnull(old.status_id,0), 0,
				old.is_manual_progress,
				old.cancel_reason_id,
				old.cancel_note,
				old.talk_id
			from #dc_contents c
				join sdocs h on h.doc_id = c.mfr_doc_id
				left join #old_contents old on old.content_id = c.content_id
				join mfr_drafts d on d.draft_id = c.draft_id

			exec tracer_log @tid, '-- restore cancel_reason_id'
			update c set cancel_reason_id = sv.cancel_reason_id, cancel_note = sv.cancel_note
			from v_sdocs_mfr_materials c
				join #dc_contents cc on cc.content_id = c.material_content_id
				join sdocs_mfr_contents_cancelreasons_saved sv on sv.parent_content_id = c.item_content_id and sv.item_id = c.material_item_id
			where c.cancel_reason_id is null

			SET IDENTITY_INSERT SDOCS_MFR_CONTENTS OFF;

			exec tracer_log @tid, '-- default supplier_id'
			declare @attr_supplier int = (select attr_id from prodmeta_attrs where code = 'закупка.КодПоставщика')

			update x set supplier_id = pa.attr_value
			from sdocs_mfr_contents x
				join #dc_contents c on c.content_id = x.content_id
				join products_attrs pa on pa.product_id = x.item_id and pa.attr_id = @attr_supplier
			where x.is_buy = 1
				and x.supplier_id is null

			exec tracer_log @tid, '-- default manager_id'
			declare @attr_manager int = (select attr_id from prodmeta_attrs where code = 'закупка.КодМенеджера')

			update x set manager_id = pa.attr_value_id
			from sdocs_mfr_contents x
				join #dc_contents c on c.content_id = x.content_id
				join products_attrs pa on pa.product_id = x.item_id and pa.attr_id = @attr_manager
			where x.is_buy = 1
				and x.manager_id is null
		
        -- insert opers
			exec tracer_log @tid, 'insert opers'
			exec mfr_drafts_calc;2 @product_id = @product_id, @use_transfer_opers = @use_transfer_opers, @tid = @tid
		
			exec tracer_log @tid, 'calc place_id'
				update x set place_id = o.place_id
				from sdocs_mfr_contents x
					join #dc_contents c on c.content_id = x.content_id
					join sdocs_mfr_opers o on o.content_id = x.content_id and o.number = 1
				where x.is_buy = 0

				update x set place_id = o.place_id
				from sdocs_mfr_contents x
					join #dc_contents c on c.content_id = x.content_id
					join sdocs_mfr_contents cp on cp.mfr_doc_id = x.mfr_doc_id and cp.product_id = x.product_id and cp.child_id = x.parent_id
						join sdocs_mfr_opers o on o.content_id = cp.content_id and o.number = 1
				where x.is_buy = 1
					and x.place_id is null
		
        -- calc item_value0, opers_wk_hours
			exec tracer_log @tid, 'calc item_value0, opers_wk_hours'

			-- opers_wk_hours
			update x
			set opers_wk_hours = isnull(xx.duration_wk_hours,0)
			from sdocs_mfr_contents x
				join #dc_docs i on i.id = x.mfr_doc_id
				left join (
					select content_id, sum(o.duration_wk * dur.factor / dur_h.factor) as duration_wk_hours
					from sdocs_mfr_opers o
						join projects_durations dur on dur.duration_id = o.duration_wk_id
						join projects_durations dur_h on dur_h.duration_id = 2
					group by content_id
				) xx on xx.content_id = x.content_id
			where x.is_buy = 0
				and isnull(x.opers_wk_hours,0) != isnull(xx.duration_wk_hours,0)

			-- sum item_value0, opers_wk_hours
			update x
			set item_value0 = xx.item_value0,
				opers_wk_hours = isnull(x.opers_wk_hours, 0) + isnull(xx.opers_wk_hours, 0)
			from sdocs_mfr_contents x
				join (
					select
						r.content_id,
						sum(isnull(r2.item_value0,0)) as item_value0,
						sum(r2.opers_wk_hours) as opers_wk_hours
					from sdocs_mfr_contents r
						join #dc_docs i on i.id = r.mfr_doc_id
						join sdocs_mfr_contents r2 on 
								r2.mfr_doc_id = r.mfr_doc_id
							and	r2.product_id = r.product_id
							and r2.node.IsDescendantOf(r.node) = 1
					where r.has_childs = 1
						and r2.has_childs = 0
					group by r.content_id
				) xx on xx.content_id = x.content_id
				join #dc_docs i on i.id = x.mfr_doc_id

			update x
			set item_value0_part = x.item_value0 / nullif(xx.item_value0,0)
			from sdocs_mfr_contents x
				join (
					select mfr_doc_id, product_id, sum(isnull(item_value0,0)) as item_value0
					from sdocs_mfr_contents
					where has_childs = 0
					group by mfr_doc_id, product_id
				) xx on xx.mfr_doc_id = x.mfr_doc_id and xx.product_id = x.product_id
				join #dc_docs i on i.id = x.mfr_doc_id
		EXEC SYS_SET_TRIGGERS 1
	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

	final:
		exec drop_temp_table '#dc_docs,#old_contents,#dc_contents'
		exec tracer_close @tid
		if @trace = 1 exec tracer_view @tid
end
GO
-- helper: build opers
create proc mfr_drafts_calc;2
	@drafts app_pkids readonly,
    @product_id int = null,
	@use_transfer_opers bit = 1,
	@tid int = 0
as
begin
	declare @docs app_pkids; insert into @docs select id from #dc_docs

	declare @filter_drafts bit = case when exists(select 1 from @drafts) then 1 else 0 end

	create table #dc_opers(
		row_id int identity primary key,
		oper_id int index ix_oper,
		mfr_doc_id int,
		product_id int,
		child_id int,
		content_id int,
		--
		place_id int,
		number int,
		operkey varchar(20),
		work_type_id int,
		type_id int,
		name varchar(100),
		resource_id int,
		predecessors varchar(100),
		duration float,
		duration_id int,
		duration_wk float,
		duration_wk_id int,
		resources_value decimal(18,2),
		q_brutto_product float
		)
		; create unique index ix_opers on #dc_opers(content_id, number)

	exec tracer_log @tid, 'build #dc_opers, seed', @level = 1
		-- build
			insert into #dc_opers(
				mfr_doc_id, product_id, child_id, content_id,			
				place_id, work_type_id, type_id, 
				number, operkey, name,
				resource_id, predecessors,
				duration, duration_id,
				duration_wk, duration_wk_id,
				resources_value,
				q_brutto_product
				)
			select
				c.mfr_doc_id, c.product_id, c.child_id, c.content_id,			
				o.place_id, o.work_type_id, o.type_id, 
				o.number, case when o.work_type_id = 1 then o.operkey end, o.name,
				rs.resource_id, o.predecessors,
				-- duration
				case 
					when c.is_buy = 1 then 1
					when isnull(d.part_q,0) = 1 then c.q_brutto_product
					else 1 
				end * o.duration, o.duration_id,
				-- 
				c.q_brutto_product * o.duration_wk, o.duration_wk_id,
				c.q_brutto_product * rs.loading_value,
				c.q_brutto_product
			from sdocs_mfr_contents c
				join #dc_docs i on i.id = c.mfr_doc_id
				join mfr_drafts_opers o on o.draft_id = c.draft_id
					join mfr_drafts d on d.draft_id = o.draft_id
					left join (
						select oper_id,
							resource_id = min(rs.resource_id),
							loading_value = sum(loading_value)
						from mfr_drafts_opers_resources r
							join mfr_resources rs on rs.resource_id = r.resource_id
						group by oper_id
					) rs on rs.oper_id = o.oper_id
			where isnull(o.is_deleted,0) = 0
				and (@filter_drafts = 0 or c.draft_id in (select id from @drafts))
                and (@product_id is null or c.product_id = @product_id)
			order by c.content_id, o.number

		-- seed
			update x set oper_id = o.oper_id
			from #dc_opers x
				join sdocs_mfr_opers o on o.content_id = x.content_id and o.number = x.number

			declare @seed_id int = isnull((select max(oper_id) from sdocs_mfr_opers), 0)

			update x
			set oper_id = @seed_id + xx.id
			from #dc_opers x
				join (
					select row_number() over (order by row_id) as id, row_id
					from #dc_opers
				) xx on xx.row_id = x.row_id
			where x.oper_id is null

	create table #dc_old_opers(
		oper_id int primary key,
		milestone_id int,
		d_after datetime,
		d_before datetime,
		d_from datetime,
		d_to datetime,
		d_from_plan datetime,
		d_to_plan datetime,
		d_to_fact datetime,
		d_from_predict datetime,
		d_to_predict datetime,
		duration_buffer int,
		duration_buffer_predict int,
		progress float,
		fact_q float,
		status_id int
		)

	exec tracer_log @tid, 'delete opers', @level = 1
		delete o
			output 
				deleted.oper_id, deleted.milestone_id,
				deleted.d_after, deleted.d_before, deleted.d_from, deleted.d_to, deleted.d_from_plan, deleted.d_to_plan, deleted.d_to_fact,
				deleted.d_from_predict, deleted.d_to_predict, deleted.duration_buffer, deleted.duration_buffer_predict,
				deleted.progress,
				deleted.fact_q,
				deleted.status_id
			into #dc_old_opers
		from sdocs_mfr_opers o
			join sdocs_mfr_contents c on c.content_id = o.content_id
				join #dc_docs i on i.id = c.mfr_doc_id
		where (@filter_drafts = 0 or c.draft_id in (select id from @drafts))
            and (@product_id is null or c.product_id = @product_id)

		update #dc_opers set duration_wk_id = 2 where duration_wk_id is null
		update #dc_opers set type_id = 0 where type_id is null

	exec tracer_log @tid, 'insert opers', @level = 1
		SET IDENTITY_INSERT SDOCS_MFR_OPERS ON;

			insert into sdocs_mfr_opers(
				oper_id,
				mfr_doc_id, product_id, child_id, content_id,
				place_id, work_type_id,
				type_id, number, operkey, name,
				resource_id, predecessors,
				plan_q,
				duration, duration_id, duration_wk, duration_wk_id, resources_value,
				-- 
				status_id, d_from, d_to, d_from_plan, d_to_plan, d_to_fact, d_from_predict, d_to_predict, d_before, d_after,
				duration_buffer, duration_buffer_predict, progress, fact_q, milestone_id
				)
			select
				x.oper_id,
				x.mfr_doc_id, x.product_id, x.child_id, x.content_id,
				x.place_id, isnull(x.work_type_id, 1),
				x.type_id, x.number, x.operkey, x.name,
				x.resource_id, x.predecessors,
				x.q_brutto_product,
				x.duration, x.duration_id, x.duration_wk, x.duration_wk_id, x.resources_value,
				-- 
				isnull(old.status_id, 0), old.d_from, old.d_to, old.d_from_plan, old.d_to_plan, old.d_to_fact, old.d_from_predict, old.d_to_predict, old.d_before, old.d_after,
				old.duration_buffer, old.duration_buffer_predict, old.progress, old.fact_q, old.milestone_id
			from #dc_opers x
				left join #dc_old_opers old on old.oper_id = x.oper_id

		SET IDENTITY_INSERT SDOCS_MFR_OPERS OFF;
			
	if @use_transfer_opers = 1
	begin
		exec tracer_log @tid, 'calc is_first, is_last', @level = 1
			exec mfr_items_calc_links @docs = @docs, @skip_links = 1, @enforce = 1 --, @tid = @tid

		exec tracer_log @tid, 'exclude virtuals', @level = 1
			-- исключаем передаточные операции (когда участок последней операции совпадает с участком первой операции родительской детали)
			create table #dc_virtual_opers(oper_id int primary key, content_id int)
				insert into #dc_virtual_opers(oper_id, content_id)
				select distinct o_last.oper_id, o_last.content_id
				from sdocs_mfr_opers o_last
					join sdocs_mfr_contents c on c.content_id = o_last.content_id
						join sdocs_mfr_contents parent on parent.mfr_doc_id = c.mfr_doc_id and parent.child_id = c.parent_id
							join sdocs_mfr_opers o_parent on o_parent.content_id = parent.content_id
				where o_last.oper_id in (select oper_id from #dc_opers)
					and o_last.is_last = 1 -- участок последней операции = участку первой родительской операции
					and isnull(o_last.is_first,0) != 1 -- операция - не единственная
					and o_last.place_id = o_parent.place_id
					and o_parent.is_first = 1
					and c.is_buy = 0 -- только для деталей
					and o_last.name like '#%' -- только авто-наименования (ручные правки не трогаем)

				delete from sdocs_mfr_opers where oper_id in (select oper_id from #dc_virtual_opers)
				exec drop_temp_table '#dc_virtual_opers'

			-- unused opers
				delete x from sdocs_mfr_opers x
				where not exists(select 1 from sdocs_mfr_contents where content_id = x.content_id)
					and mfr_doc_id in (select id from #dc_docs)
	end

	exec tracer_log @tid, 'calc links (after)', @level = 1
	exec mfr_items_calc_links @docs = @docs, @enforce = 1

	exec drop_temp_table '#dc_opers,#dc_old_opers'
end
go
-- helper: apply swaps
create proc mfr_drafts_calc;10
	-- #dc_contents
	@tid int
as
begin
	declare @tid_msg varchar(max)

	create table #sw_orders(id int primary key)
		insert into #sw_orders select distinct mfr_doc_id from #dc_contents

		set @tid_msg = concat('#sw_orders: ', (select count(*) from #sw_orders), ' rows')
		exec tracer_log @tid, @tid_msg, @level = 1

	-- tables
		create table #sw_require(
			row_id int identity primary key,
			mfr_doc_id int,
			item_id int,
			content_child_id int index ix_content,
			unit_name varchar(20),
			value float,
			swap_id int,
			index ix_join (mfr_doc_id, item_id)
			)

		create table #sw_provide(
			row_id int identity primary key,
			swap_id int,
			mfr_doc_id int,
			item_id int index ix_item,
			unit_name varchar(20),
			new_item_id int,
			new_unit_name varchar(20),
			q_factor float,
			value float,
			index ix_join (mfr_doc_id, item_id)
			)

		create table #sw_provide_all(
			row_id int identity primary key,
			swap_id int,
			item_id int index ix_item,
			unit_name varchar(20),
			new_item_id int,
			new_unit_name varchar(20),
			q_factor float,
			index ix_join (item_id)
			)

		create table #sw_result(
			row_id int identity primary key,
			src_row_id int index ix_src_row,
			swap_id int,
			mfr_doc_id int,
			item_id int,
			new_item_id int,
			content_child_id int index ix_content,
			unit_name varchar(20),
			new_unit_name varchar(20),
			value float,
			q_factor float,
			slice varchar(10),
			index ix_join (mfr_doc_id, item_id)
			)
		
		create table #sw_result_all(
			content_child_id int primary key,
			mfr_doc_id int,
			item_id int,
			swap_id int,
			new_item_id int,
			unit_name varchar(20),
			new_unit_name varchar(20),
			value float
			)

	-- #sw_items
		create table #sw_items(item_id int primary key)
			insert into #sw_items(item_id)
			select distinct product_id from mfr_swaps_products x
				join mfr_swaps sw on sw.doc_id = x.doc_id and sw.is_deleted = 0
				join mfr_sdocs mfr on x.mfr_number in ('ALL', mfr.number)
					join #sw_orders i on i.id = mfr.doc_id

		set @tid_msg = concat('#sw_items: ', (select count(*) from #sw_items), ' rows')
		exec tracer_log @tid, @tid_msg, @level = 1

	exec tracer_log @tid, '#sw_require', @level = 1
		insert into #sw_require(content_child_id, mfr_doc_id, item_id, unit_name, value)
		select x.child_id, x.mfr_doc_id, x.item_id, x.unit_name, x.q_brutto_product
		from #dc_contents x
			join #sw_orders i on i.id = x.mfr_doc_id
			join #sw_items ii on ii.item_id = x.item_id
		where x.is_buy = 1
			and x.q_brutto_product > 0
		order by x.mfr_doc_id, x.child_id

		-- select p.name, r.* from #sw_require r
		-- 	join products p on p.product_id = r.item_id
		-- where r.item_id = 24428
		-- return

		set @tid_msg = concat('#sw_require: ', (select count(*) from #sw_require), ' rows')
		exec tracer_log @tid, @tid_msg, @level = 1

	exec tracer_log @tid, '#sw_provide_all', @level = 1
		insert into #sw_provide_all(
			swap_id, item_id, unit_name, new_item_id, new_unit_name, q_factor
			)		
		select 
			sw.doc_id,
			x.product_id,
			u1.name,
			x.dest_product_id,
			u2.name,
			x.dest_quantity / x.quantity
		from mfr_swaps_products x
			join mfr_swaps sw on sw.doc_id = x.doc_id and sw.is_deleted = 0
			join products_units u1 on u1.unit_id = x.unit_id
			join products_units u2 on u2.unit_id = x.dest_unit_id
		where x.quantity > 0
			and x.mfr_number = 'ALL'
			and x.product_id != x.dest_product_id

		update x set item_id = sw.new_item_id, unit_name = sw.new_unit_name, [value] = x.[value] * sw.q_factor,
			swap_id = sw.swap_id
			output 
				inserted.content_child_id, inserted.mfr_doc_id, deleted.item_id,
				inserted.swap_id, inserted.item_id, deleted.unit_name, inserted.unit_name, inserted.[value]
			into #sw_result_all(
				content_child_id, mfr_doc_id, item_id, 
				swap_id, new_item_id, unit_name, new_unit_name, [value]
				)
		from #sw_require x
			join #sw_provide_all sw on sw.item_id = x.item_id
		
		delete x from #sw_require x
			join #sw_result_all r on r.content_child_id = x.content_child_id

		-- select p.name, r.* from #sw_result_all r
		-- 	join products p on p.product_id = r.item_id
		-- -- where p.name like '%6002000239%'
		-- order by draft_id, item_id
		-- return

	exec tracer_log @tid, '#sw_provide', @level = 1
		insert into #sw_provide(
			swap_id, mfr_doc_id, item_id, unit_name, new_item_id, new_unit_name, q_factor, value
			)		
		select
			swap_id, mfr_doc_id, item_id, unit_name, new_item_id, new_unit_name, isnull(nullif(q_factor,0),1), quantity
		from (
			select 
				swap_id = x.doc_id,
				x.mfr_doc_id,
				x.d_doc,
				item_id = x.product_id,
				unit_name = u1.name,
				new_item_id = x.dest_product_id,
				new_unit_name = u2.name,
				q_factor = x.dest_quantity / x.quantity,
				x.quantity
			from (
				select 
					sw.doc_id,
					sw.d_doc, 
					note = left(x.note, 50),
					mfr_doc_id = mfr.doc_id,
					x.product_id,
					x.unit_id,
					x.quantity,
					x.dest_product_id,
					x.dest_unit_id,
					x.dest_quantity
				from mfr_swaps_products x
					join mfr_swaps sw on sw.doc_id = x.doc_id and sw.is_deleted = 0
					join sdocs_mfr mfr on mfr.number = x.mfr_number
						join #sw_orders i on i.id = mfr.doc_id
				where x.quantity > 0
					and (sw.status_id = 100)
				) x
				join products_units u1 on u1.unit_id = x.unit_id
				join products_units u2 on u2.unit_id = x.dest_unit_id
			) xx
		where xx.quantity > 0
			and xx.new_item_id is not null
		order by mfr_doc_id, item_id, d_doc

		-- select p.name, r.* from #sw_provide r
		-- 	join products p on p.product_id = r.item_id
		-- where r.swap_id = 539894
		-- return

		set @tid_msg = concat('#sw_provide: ', (select count(*) from #sw_provide), ' rows')
		exec tracer_log @tid, @tid_msg, @level = 1

	exec tracer_log @tid, 'swap (FIFO)', @level = 1
		declare @fid uniqueidentifier set @fid = newid()

		insert into #sw_result(
			src_row_id, mfr_doc_id, item_id, content_child_id, unit_name,
			swap_id, new_item_id, new_unit_name, q_factor, value,
			slice
			)
		select
			-- old
			r.row_id, r.mfr_doc_id, r.item_id, r.content_child_id, r.unit_name,
			-- new
			p.swap_id, p.new_item_id, p.new_unit_name, p.q_factor, f.value * p.q_factor,
			'mix'
		from #sw_require r
			join #sw_provide p on p.mfr_doc_id = r.mfr_doc_id and p.item_id = r.item_id
			cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
		order by r.row_id, p.row_id

		-- left
			insert into #sw_result(
				src_row_id, mfr_doc_id, item_id, content_child_id, unit_name, new_item_id, new_unit_name, q_factor, value, slice
				)
			select
				r.row_id, r.mfr_doc_id, r.item_id, r.content_child_id, r.unit_name,
				r.item_id, r.unit_name, 1, f.value,
				'left'
			from dbo.fifo_left(@fid) f
				join #sw_require r on r.row_id = f.row_id
					join (
						select distinct item_id from #sw_result
					) dr on dr.item_id = r.item_id
			where f.value > 0.00001

			exec fifo_clear @fid

	exec tracer_log @tid, 'merge swap(FIFO) + swap(ALL)', @level = 1
		insert into	#sw_result(mfr_doc_id, item_id, content_child_id, unit_name, swap_id, new_item_id, new_unit_name, q_factor, value)
		select mfr_doc_id, item_id, content_child_id, unit_name, swap_id, new_item_id, unit_name, 1, [value]
		from #sw_result_all

		-- select p.name, r.* from #sw_result r
		-- 	join products p on p.product_id = r.item_id
		-- where r.item_id = 45034
		-- return

		set @tid_msg = concat('#sw_result: ', (select count(*) from #sw_result), ' rows')
		exec tracer_log @tid, @tid_msg, @level = 1

	exec tracer_log @tid, 'apply to #dc_contents', @level = 1
		select x.* into #dc_contents_old from #dc_contents x
			join (
				select distinct content_child_id from #sw_result	
			) r on r.content_child_id = x.child_id

		delete x from #dc_contents x
			join #sw_result	r on r.content_child_id = x.child_id

		insert into #dc_contents(
			mfr_doc_id, product_id, draft_id,
            item_id, swapped_item_id, swap_id, is_swap,
			level_id, parent_id, parent_item_id,
			place_id, item_type_id, is_buy,
			unit_name, q_brutto_product,
			item_price0, d_doc
			)
		select 
			r.mfr_doc_id, c.product_id, c.draft_id,
            r.new_item_id, r.item_id, r.swap_id,
            case when r.item_id != r.new_item_id then 1 end,
			c.level_id, c.parent_id, c.parent_item_id,
			c.place_id, c.item_type_id, c.is_buy, 
			r.new_unit_name, 
			r.value,
			c.item_price0, c.d_doc
		from #sw_result r
			join #dc_contents_old c on c.child_id = r.content_child_id

    final:
		exec drop_temp_table '#sw_orders,#sw_items,#sw_require,#sw_provide,#sw_provide_all,#sw_result,#sw_result_all,#dc_contents_old'
end
go
