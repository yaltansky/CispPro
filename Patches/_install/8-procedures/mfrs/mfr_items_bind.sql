if object_id('mfr_items_bind') is not null drop proc mfr_items_bind
go
-- exec mfr_items_bind @mol_id = 1000, @route_id = 45
create proc mfr_items_bind
	@mol_id int,
	@action varchar(50) = null,
	@status_id int = null, -- установить статус деталей производстенного плана (в буфере)
	@milestone_id int = null, -- установить веху
	@milestone_slice varchar(10) = null, -- items | opers
    @route_use_defaults bit = 0, -- использовать длительности из справочника номенклатуры
	@route_id int = null, -- привязать операции (маршрут @route_id) к деталям производстенного плана (в буфере)
	@route_duration int = null, -- длительность операции (дн) <-- используется для материалов
	@content_id int = null,
	@context varchar(20) = null,
	@d_after datetime = null, -- привязать ограничение "Начать после"
	@d_before datetime = null, -- привязать ограничение "Завершить до"
	@use_draft_date bit = 0, -- использовать дату тех.выписки в качестве "Начать после"
	@supplier_id int = null,
	@manager_id int = null,
	@progress float = null,
	@var_pdm_id int = null,
	@var_variant_number int = null,
	@var_batchmode bit = 0,
	@cancel_reason_id int = null,
	@cancel_note varchar(100) = null
as
begin
    set nocount on;

    exec sys_set_user @mol_id

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
        declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 'action = ', @action)
        exec tracer_log @tid, @tid_msg      

	-- declare
		declare @today datetime = dbo.today()
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
		declare @buffer app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
		declare @docs app_pkids
		declare @drafts app_pkids
		declare @contents app_pkids
		declare @attr_id int

    if @mol_id != all(
        select distinct manager_id from sdocs_mfr_contents c
        join @buffer i on i.id = c.content_id
        )
    begin
	    exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'
        if @@error != 0 return
    end

	if @status_id is not null
	begin
		update sdocs_mfr_contents
		set status_id = @status_id
		where content_id in (select id from @buffer)
	end

	if @milestone_id is not null
	begin
		if @milestone_slice = 'items'
		begin
			update x set milestone_id = nullif(@milestone_id,0)
			from sdocs_mfr_opers x
				join @buffer i on i.id = x.content_id
			where x.is_last = 1

			insert into sdocs_mfr_milestones(doc_id, product_id, attr_id)
			select distinct x.mfr_doc_id, sp.product_id, milestone_id
			from sdocs_mfr_opers x
				join @buffer i on i.id = x.content_id
				join sdocs_products sp on sp.doc_id = x.mfr_doc_id
			where x.is_last = 1
				and x.milestone_id is not null
				and not exists(select 1 from sdocs_mfr_milestones where doc_id = x.mfr_doc_id and product_id = sp.product_id and attr_id = x.milestone_id)
		end
		
		else begin
			delete from @buffer; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfo')
			
			update x set milestone_id = nullif(@milestone_id,0)
			from sdocs_mfr_opers x
				join @buffer i on i.id = x.oper_id

			insert into sdocs_mfr_milestones(doc_id, product_id, attr_id)
			select distinct mfr_doc_id, sp.product_id, milestone_id
			from sdocs_mfr_opers x
				join sdocs_products sp on sp.doc_id = x.mfr_doc_id
				join @buffer i on i.id = x.oper_id
			where x.milestone_id is not null
				and not exists(select 1 from sdocs_mfr_milestones where doc_id = x.mfr_doc_id and product_id = sp.product_id and attr_id = x.milestone_id)
		end
	end

	BEGIN TRY
	BEGIN TRANSACTION

		-- clone drafts
		if @action = 'CloneDraftContext'
		begin
			declare @draft_id int = (select draft_id from sdocs_mfr_contents where content_id = @content_id)
			select @draft_id = isnull(main_id,draft_id) from sdocs_mfr_drafts where draft_id = @draft_id

			if @draft_id is not null
			begin			
				if @context = 'spread-plan'
					insert into @drafts select distinct isnull(d.main_id,x.draft_id)
					from sdocs_mfr_contents x
						join sdocs_mfr_drafts d on d.draft_id = x.draft_id
						join sdocs_mfr_contents c on c.plan_id = x.plan_id and c.item_id = x.item_id
					where c.content_id = @content_id
				else
					insert into @drafts values(@draft_id)

				delete from sdocs_mfr_drafts_opers where draft_id in (select id from @drafts)

				insert into sdocs_mfr_drafts_opers(
					draft_id,
					work_type_id, type_id, number, name, place_id, predecessors,
					duration, duration_id, duration_wk, duration_wk_id
					)
				select 
					d.id,
					o.work_type_id, o.type_id, o.number, o.name, o.place_id, o.predecessors,
					o.duration, o.duration_id,
					o.duration_wk / c.q_brutto_product,
					o.duration_wk_id
				from sdocs_mfr_opers o
					join sdocs_mfr_contents c on c.content_id = o.content_id
					, @drafts d
				where o.content_id = @content_id
			end
		end

		-- bind pdm opers (defaults)
		if @action = 'BindPdmOpers'
		begin
			exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Admin'

			declare @max_rows int = cast(dbo.app_registry_value('mfr_items_bind.BindPdmOpers.MaxRows') as int)
			if (select count(*) from @buffer) > @max_rows
				raiserror('Количество деталей в буфере превышает допустимое количество (%d).', 16, 1, @max_rows)
			exec mfr_items_bind;10 @mol_id = @mol_id
		end
		
        -- add to Gantt diagram
		if @action = 'AddToGantt'
		begin
            set @attr_id =  (select attr_id from prodmeta_attrs where code = 'NodeGantt');

            insert into sdocs_mfr_drafts_attrs(draft_id, attr_id, add_date)
            select distinct draft_id, @attr_id, getdate()
            from sdocs_mfr_contents c
                join @buffer i on i.id = c.content_id;
		end
		
        -- remove from Gantt diagram
        if @action = 'RemoveFromGantt'
		begin
            set @attr_id =  (select attr_id from prodmeta_attrs where code = 'NodeGantt');

            delete x from sdocs_mfr_drafts_attrs x
                join sdocs_mfr_contents c on c.draft_id = x.draft_id
                    join @buffer i on i.id = c.content_id
            where x.attr_id = @attr_id;
		end

		-- bind defaults durations
		if @route_use_defaults = 1
        begin
            print 'apply @route_use_defaults'
            exec mfr_items_bind;20 @mol_id = @mol_id
        end

        -- bind route_id
        if @route_id is not null 
		begin
			exec printlog '@contents'
				insert into @contents select c.content_id from sdocs_mfr_contents c
					join @buffer buf on buf.id = c.content_id
				where c.draft_id is not null

            -- drop table _mfr_items_bind
            -- create table _mfr_items_bind(
            --     mol_id int,
            --     add_date datetime default getdate(),
            --     content_id int,
            --     route_id int,
            --     duration int
            --     );
            -- -- TRACE DURATION
            -- INSERT INTO _MFR_ITEMS_BIND(MOL_ID, ROUTE_ID, CONTENT_ID)
            -- SELECT @MOL_ID, @ROUTE_ID, ID
            -- FROM @CONTENTS;

			exec printlog '@drafts'
				insert into @drafts select distinct draft_id from sdocs_mfr_contents where content_id in (select id from @contents)

			exec printlog 'update opers (of drafts)'
				EXEC SYS_SET_TRIGGERS 0
					delete x from sdocs_mfr_drafts_opers x where x.draft_id in (select id from @drafts)
				EXEC SYS_SET_TRIGGERS 1
				
				insert into sdocs_mfr_drafts_opers(
					draft_id,
					place_id, work_type_id, type_id, name, number,
					duration, duration_id, duration_wk, duration_wk_id,
					predecessors, is_first, is_last,
					add_mol_id
					)
				select
					i.id,
					x.place_id,
					x.work_type_id,
					x.type_id,
					x.name, x.number,
					x.duration, x.duration_id, x.duration_wk, x.duration_wk_id,
					x.predecessors, x.is_first, x.is_last,
					@mol_id
				from @drafts i
					join mfr_routes_details x on x.route_id = @route_id
			
			exec printlog 'update contents'
				insert into @docs
				select distinct mfr_doc_id from sdocs_mfr_contents where content_id in (select id from @contents)

				if (select count(*) from @docs) < 100
					exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs
				
				else begin
					EXEC SYS_SET_TRIGGERS 0
						delete x from sdocs_mfr_opers x where x.content_id in (select id from @contents)
					EXEC SYS_SET_TRIGGERS 1

					insert into sdocs_mfr_opers(
						mfr_doc_id, product_id, child_id, content_id,
						place_id, work_type_id, type_id, name, number,
						status_id, plan_q,
						duration, duration_id, duration_wk, duration_wk_id,
						predecessors, is_first, is_last,
						add_mol_id
						)
					select
						c.mfr_doc_id, c.product_id, c.child_id, c.content_id,
						x.place_id,
						x.work_type_id,
						x.type_id,
						x.name,
						x.number,
						0, -- status_id
						c.q_brutto_product,
						x.duration, x.duration_id, x.duration_wk, x.duration_wk_id,
						x.predecessors, x.is_first, x.is_last,
						@mol_id
					from sdocs_mfr_contents c
						join sdocs_mfr_drafts_opers x on x.draft_id = c.draft_id
					where c.content_id in (select id from @contents)

					exec mfr_items_calc_links @docs = @docs, @enforce = 1
				end

				goto products_attrs_durations
		end

		-- bind duration
		if @route_duration is not null 
		begin
            -- -- TRACE DURATION
		    -- INSERT INTO _MFR_ITEMS_BIND(MOL_ID, CONTENT_ID, DURATION)
            -- SELECT @MOL_ID, ID, @ROUTE_DURATION
            -- FROM @BUFFER;
	
            exec sys_set_triggers 0
				update x set duration = @route_duration, update_date = getdate(), update_mol_id = @mol_id
				from mfr_drafts_opers x
					join sdocs_mfr_contents c on c.draft_id = x.draft_id
						join @buffer buf on buf.id = c.content_id

				update x set duration = @route_duration, update_date = getdate(), update_mol_id = @mol_id
				from sdocs_mfr_opers x
					join @buffer buf on buf.id = x.content_id
			exec sys_set_triggers 1

			products_attrs_durations:
				declare @attr_duration int = (select attr_id from prodmeta_attrs where name = 'закупка.ТранзитныйСрок')
				declare @items_durations table(item_id int primary key, duration float)

				insert into @items_durations(item_id, duration)
				select distinct c.item_id, o.duration
				from sdocs_mfr_opers o
					join sdocs_mfr_contents c on c.content_id = o.content_id
						join @buffer i on i.id = c.content_id

				-- update durations
				update x set attr_value = i.duration, update_date = getdate(), update_mol_id = @mol_id
				from products_attrs x
					join @items_durations i on i.item_id = x.product_id and x.attr_id = @attr_duration
				
				-- add durations
				insert into products_attrs(product_id, attr_id, attr_value, add_date, add_mol_id)
				select item_id, @attr_duration, duration, getdate(), @mol_id
				from @items_durations i
				where not exists(select 1 from products_attrs where product_id = i.item_id and attr_id = @attr_duration)
		end

		-- bind dates
		if @d_after is not null or @d_before is not null
		begin
			exec mfr_items_buffer_action @mol_id = @mol_id, @action = 'CheckAccessAdmin'

			set @d_after = case when @d_after <= '1900-01-01' then null else @d_after end
			set @d_before = case when @d_before <= '1900-01-01' then null else @d_before end
			
			update x set d_after = @d_after, d_before = @d_before
			from sdocs_mfr_contents x
				join @buffer buf on buf.id = x.content_id
		end

		-- bind progress
		if @progress is not null
		begin
			declare @tmp_progress float
			
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Admin'

			update x
			set @tmp_progress = 
					case
						when @progress is null then 1.0 * datediff(d, x.d_from, @today) / nullif(datediff(d, x.d_from, x.d_to), 0)
						else @progress
					end,
				@tmp_progress = 
					case 
						when @tmp_progress < 0 then 0
						when @tmp_progress >= 0.99 then 1
						else @tmp_progress
					end,
				progress = @tmp_progress,
				status_id = case when @tmp_progress = 1 then 100 else x.status_id end,
				d_to_fact = case when @tmp_progress = 1 then @today end,
				update_date = getdate(),
				update_mol_id = @mol_id
			from sdocs_mfr_opers x
				join @buffer buf on buf.id = x.content_id

			update x set is_manual_progress = 
				case
					when (select count(*) from mfr_sdocs_opers where content_id = x.content_id and progress > 0) > 0 then 1
					else 0
				end,
				update_date = getdate(),
				update_mol_id = @mol_id
			from mfr_sdocs_contents x
				join @buffer buf on buf.id = x.content_id

		end	

		-- bind supplier
		if @supplier_id is not null
		begin
			update x set supplier_id = @supplier_id
			from mfr_sdocs_contents x
				join @buffer buf on buf.id = x.content_id

			set @attr_id = (select attr_id from prodmeta_attrs where code = 'закупка.КодПоставщика')
			
			delete x from products_attrs x
				join (
					select item_id from mfr_sdocs_contents c
						join @buffer buf on buf.id = c.content_id
				) c on c.item_id = x.product_id
			where x.attr_id = @attr_id

			insert into products_attrs(product_id, attr_id, attr_value)
			select distinct x.item_id, @attr_id, @supplier_id
			from mfr_sdocs_contents x
				join @buffer buf on buf.id = x.content_id
		end

		-- bind manager
		if @manager_id is not null
		begin
			if dbo.isinrole(@mol_id, 'admin') = 0
				and (select count(*) from @buffer) > 500		
					raiserror('В методе присвоения менеджера можно задействовать не более 500 строк потребности.', 16, 1)

			update x set manager_id = @manager_id
			from mfr_sdocs_contents x
				join @buffer buf on buf.id = x.content_id

			set @attr_id = (select attr_id from prodmeta_attrs where code = 'закупка.КодМенеджера')
			
			delete x from products_attrs x
				join (
					select item_id from mfr_sdocs_contents c
						join @buffer buf on buf.id = c.content_id
				) c on c.item_id = x.product_id
			where x.attr_id = @attr_id

			insert into products_attrs(product_id, attr_id, attr_value_id)
			select distinct x.item_id, @attr_id, @manager_id
			from mfr_sdocs_contents x
				join @buffer buf on buf.id = x.content_id
				join mols on mols.mol_id = @manager_id
		end

		-- bind pdm opers variant
		if @var_variant_number is not null
		begin
			exec printlog '@contents'
				if 1 < (
                    select count(distinct c.item_id) from sdocs_mfr_contents c
					    join @buffer buf on buf.id = c.content_id
                    )
					raiserror('Выбранные детали должны ссылаться на одну карточку библиотеки ДСЕ.', 16, 1)

				insert into @contents select c.content_id from sdocs_mfr_contents c
					join @buffer buf on buf.id = c.content_id
				where c.draft_id is not null
				
				insert into @drafts select distinct c.draft_id from sdocs_mfr_contents c
					join @buffer buf on buf.id = c.content_id
				where c.draft_id is not null

			exec printlog 'sync opers, executors, resources'
				delete x from mfr_drafts_pdm x
					join @drafts i on i.id = x.draft_id
				where x.route_number is not null
				-- drafts options
				insert into mfr_drafts_pdm(draft_id, pdm_id, route_number, add_mol_id)
				select id, @var_pdm_id, @var_variant_number, @mol_id
				from @drafts
				-- bind pdm_id
				update x set pdm_id = @var_pdm_id
				from mfr_drafts x
					join @drafts i on i.id = x.draft_id
				-- sync opers
				exec mfr_drafts_from_pdm;2 @mol_id = @mol_id, @drafts = @drafts, @sync_mode = 'opers'

			exec printlog 'update contents opers'
				insert into @docs select distinct mfr_doc_id from sdocs_mfr_contents where content_id in (select id from @contents)

				EXEC SYS_SET_TRIGGERS 0
					declare @milestones table(
						content_id int, oper_number int, milestone_id int, milestone_name varchar(250),
						index ix_join (content_id, oper_number)
						)
						insert into @milestones(content_id, oper_number, milestone_id, milestone_name)
						select content_id, number, milestone_id, milestone_name
						from sdocs_mfr_opers 
						where content_id in (select id from @contents)
							and milestone_id is not null

					delete x from sdocs_mfr_opers x where x.content_id in (select id from @contents)
				EXEC SYS_SET_TRIGGERS 1

				insert into sdocs_mfr_opers(
					mfr_doc_id, product_id, child_id, content_id,
					place_id, work_type_id, type_id, name, number, operkey,
					milestone_id, milestone_name,
					status_id, plan_q,
					duration, duration_id, duration_wk, duration_wk_id,
					predecessors, is_first, is_last,
					add_mol_id
					)
				select
					c.mfr_doc_id, c.product_id, c.child_id, c.content_id,
					x.place_id, x.work_type_id, x.type_id, x.name, x.number, x.operkey,
					ms.milestone_id, ms.milestone_name,				
					0 /*status_id*/, c.q_brutto_product,
					x.duration, x.duration_id, x.duration_wk, x.duration_wk_id,
					x.predecessors, x.is_first, x.is_last,
					@mol_id
				from sdocs_mfr_contents c
					join mfr_drafts_opers x on x.draft_id = c.draft_id
					left join @milestones ms on ms.content_id = c.content_id and ms.oper_number = x.number
				where c.content_id in (select id from @contents)

				update x set x.resource_id = rs.resource_id
				from sdocs_mfr_opers x
					join sdocs_mfr_contents c on c.content_id = x.content_id
						join @contents i on i.id = c.content_id
						join mfr_drafts_opers oo on oo.draft_id = c.draft_id and oo.number = x.number
							join mfr_drafts_opers_resources rs on rs.oper_id = oo.oper_id
				
				if @var_batchmode = 0
				begin
					exec mfr_items_calc_links @docs = @docs, @enforce = 1
					exec mfr_opers_calc @mol_id = @mol_id, @docs = @docs, @mode = 3 -- ПДО
				end
		end

		-- bind cancel option
		if @cancel_reason_id is not null
		begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'superadmin'

			update x set 
				status_id = case when @cancel_reason_id = 0 then 0 else 100 end,
				progress = case when @cancel_reason_id = 0 then 0 else 1 end,
				update_mol_id = @mol_id, update_date = getdate()
			from sdocs_mfr_opers x
				join @buffer i on i.id = x.content_id

			update x set 
				cancel_reason_id = nullif(@cancel_reason_id, 0),
				cancel_note = @cancel_note,
				is_manual_progress = 0,
				update_mol_id = @mol_id, update_date = getdate()
			from sdocs_mfr_contents x
				join @buffer i on i.id = x.content_id

			delete sv from sdocs_mfr_contents_cancelreasons_saved sv
				join v_sdocs_mfr_materials c on c.item_content_id = sv.parent_content_id and c.item_id = sv.item_id
					join @buffer i on i.id = c.material_content_id

			insert into sdocs_mfr_contents_cancelreasons_saved(parent_content_id, item_id, cancel_reason_id, cancel_note, add_mol_id)
			select c.item_content_id, c.item_id, min(c.cancel_reason_id), min(c.cancel_note), @mol_id
			from v_sdocs_mfr_materials c
				join @buffer i on i.id = c.material_content_id
			group by c.item_content_id, c.item_id
		end

		if @use_draft_date = 1
		begin
			update x set d_after = d.d_doc
			from sdocs_mfr_contents x
				join @buffer buf on buf.id = x.content_id
				join mfr_drafts d on d.draft_id = x.draft_id
		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) = error_message()
		raiserror (@err, 16, 3)
	END CATCH

    -- trace end
        exec tracer_close @tid
end
go
-- helper: bind pdm opers
create proc mfr_items_bind;10
	@mol_id int
as
begin

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')

	declare @contents_test table(
		content_id int primary key,
		item_id int, c_opers int, c_pdms int, c_pdm_opers_vars int, c_pdm_opers int,
		pdm_id int, pdm_route_number int, selected_route_number int,
		is_ok bit
		)
		insert into @contents_test(content_id, item_id, c_opers, c_pdms, c_pdm_opers_vars, c_pdm_opers, pdm_id, pdm_route_number, selected_route_number)
		select c.content_id, max(c.item_id), count(*), count(distinct pdm.pdm_id), count(distinct oo.variant_number), count(*),
			max(pdm.pdm_id), max(oo.variant_number), max(pdm2.route_number)
		from sdocs_mfr_contents c
			join @buffer buf on buf.id = c.content_id
			join sdocs_mfr_opers o on o.content_id = c.content_id
			join mfr_pdms pdm on pdm.item_id = c.item_id and pdm.is_deleted = 0
				join mfr_pdm_opers oo on oo.pdm_id = pdm.pdm_id and isnull(oo.is_deleted,0) = 0
			left join mfr_drafts_pdm pdm2 on pdm2.draft_id = c.draft_id and pdm2.route_number is not null
		group by c.content_id

		update @contents_test set is_ok = 1 where 
				c_pdms = 1  -- вариант исполнения один
			and (
				c_pdm_opers_vars = 1 -- вариант маршрута один
				or selected_route_number is not null
				)
			and c_opers = c_pdm_opers -- совпадает кол-во операций

	declare @items app_pkids
		insert into @items select distinct item_id from @contents_test where is_ok = 1
	
	declare c_items cursor local read_only for select item_id = id from @items
	declare @item_id int
	
	open c_items; fetch next from c_items into @item_id

		while (@@fetch_status != -1)
		begin
			if (@@fetch_status != -2)
			begin
				declare @var_pdm_id int = (select top 1 pdm_id from @contents_test where item_id = @item_id)
				declare @var_variant_number int = (select top 1 pdm_route_number from @contents_test where item_id = @item_id)
				
				-- adjust buffer
					exec objs_buffer_clear @mol_id, 'mfc'
					
					insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
					select @buffer_id, 'mfc', content_id, 0 from @contents_test
					where item_id = @item_id and is_ok = 1
				
				-- apply bind
					exec mfr_items_bind @mol_id = @mol_id, @var_pdm_id = @var_pdm_id, @var_variant_number = @var_variant_number,
						@var_batchmode = 1

				-- delete succeeded
					delete from @contents_test where item_id = @item_id and is_ok = 1
			end
			--
			fetch next from c_items into @item_id
		end

	close c_items; deallocate c_items

	-- calc links
		declare @docs app_pkids
		insert into @docs select distinct mfr_doc_id from sdocs_mfr_contents where content_id in (select id from @buffer)
			and content_id not in (select content_id from @contents_test)
		
		exec mfr_items_calc_links @docs = @docs, @enforce = 1

	-- adjust final buffer
		exec objs_buffer_clear @mol_id, 'mfc'
		
		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'mfc', content_id, 0 from @contents_test
end
go
-- helper: bind defaults durations (materials)
create proc mfr_items_bind;20
    @mol_id int
as
begin
    declare @buffer app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
	
    -- #materials
		declare @attr_duration int = (select attr_id from prodmeta_attrs where name = 'закупка.ТранзитныйСрок')

		create table #materials(
			mfr_doc_id int,
			draft_id int primary key,
			item_id int index ix_item,
			last_draft_id int,
			def_duration float
			)
		insert into #materials(mfr_doc_id, item_id, draft_id, def_duration)
		select distinct d.mfr_doc_id, d.item_id, d.draft_id, pa.attr_value_number
		from mfr_drafts d
			join sdocs_mfr_contents c on c.draft_id = d.draft_id
                join @buffer i on i.id = c.content_id
			join products_attrs pa on pa.attr_id = @attr_duration and pa.product_id = d.item_id
		where d.is_buy = 1 
			and not exists(select 1 from mfr_drafts_opers where draft_id = d.draft_id)

		update x set 
			last_draft_id = xx.last_draft_id
		from #materials x
			join (
				select d.item_id, last_draft_id = min(oo.draft_id)
				from mfr_drafts d
					join #materials m on m.item_id = m.item_id
					join mfr_drafts_opers oo on oo.draft_id = d.draft_id
				where d.is_buy = 1 and d.is_deleted = 0
				group by d.item_id
			) xx on xx.item_id = x.item_id

        delete from #materials where last_draft_id is null

    -- mfr_drafts_opers
        declare @drafts_affected table(draft_id int)

        insert into mfr_drafts_opers(
            draft_id, place_id, number, name, duration, duration_id, predecessors, is_first, is_last, work_type_id
            )
            output inserted.draft_id into @drafts_affected
        select
            m.draft_id, place_id, number, name, 
            isnull(m.def_duration, d.duration), 3 /* дни */,
            predecessors, is_first, is_last, work_type_id
        from mfr_drafts_opers d
            join #materials m on m.last_draft_id = d.draft_id
        where isnull(d.is_deleted,0) = 0

    -- sdocs_mfr_opers
        insert into sdocs_mfr_opers(
            mfr_doc_id, product_id, content_id,
            place_id, number, name, duration, duration_id, predecessors, is_first, is_last, work_type_id
            )
        select
            c.mfr_doc_id, c.product_id, c.content_id,
            x.place_id, x.number, x.name,
            isnull(m.def_duration, x.duration), 3 /* дни */,
            x.predecessors, x.is_first, x.is_last, x.work_type_id
        from sdocs_mfr_contents c
            join #materials m on m.draft_id = c.draft_id
                join mfr_drafts_opers x on x.draft_id = m.draft_id	
        where not exists(select 1 from sdocs_mfr_opers where content_id = c.content_id and number = x.number)

    -- calc links
        declare @docs app_pkids
        insert into @docs select distinct mfr_doc_id from mfr_drafts d
            join @drafts_affected a on a.draft_id = d.draft_id
        exec mfr_items_calc_links @docs = @docs, @enforce = 1
            
    exec drop_temp_table '#materials'
end
go
