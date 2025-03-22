if object_id('mfr_items_calc_links') is not null drop proc mfr_items_calc_links
go
-- exec mfr_items_calc_links @plan_id = 4, @trace = 1
create proc mfr_items_calc_links
	@plan_id int = null,
	@doc_id int = null,
	@docs app_pkids readonly,
	@content_id int = null,
	@skip_links bit = 0,
	@enforce bit = 0,
	@trace bit = 0,
	@tid int = null
as
begin

	set nocount on;

	-- prepare
		if @plan_id is not null
			and @enforce = 0
			and exists(select 1 from mfr_plans where plan_id = @plan_id and d_calc_links is not null) 
		begin
			return -- nothing todo (caching)
		end

		if @doc_id is not null
			and @enforce = 0
			and exists(select 1 from sdocs where doc_id = @doc_id and d_calc_links is not null) 
		begin
			return -- nothing todo (caching)
		end

		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid_msg varchar(max)

		if @tid is null
			exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
		else begin
			set @tid_msg = '--' + @proc_name + ' started'
			exec tracer_log @tid, @tid_msg
		end

		create table #icl_docs(id int primary key)
		
		if @plan_id is not null
			insert into #icl_docs select doc_id from sdocs where plan_id = @plan_id
		else if @doc_id is not null 
			insert into #icl_docs select @doc_id
		else 
			insert into #icl_docs select id from @docs

		create table #icl_items(id int primary key)
			if @content_id is null
				insert into #icl_items select c.content_id from sdocs_mfr_contents c
					join #icl_docs i on i.id = c.mfr_doc_id
				where c.is_deleted = 0
			else
				insert into #icl_items select content_id from sdocs_mfr_contents where content_id = @content_id

		if not exists(select 1 from #icl_items)
			return -- nothing todo (no items)

		declare @is_first bit

	exec tracer_log @tid, 'set predecessors'
		-- признак is_first - первая операция кроме операции с типом "КР" (конструирование, WORK_TYPE_ID = 4),
		-- поскольку конструирование может выполняться одновременно для всех узлов состава изделия
		
		declare @predecessors varchar(30)

		update x
		set @predecessors = replace(replace(x.predecessors, ' ', ';'), ',', ';'),
			is_last = case when l.next_id is null then 1 end,
			is_first = null,
			prev_id = l.prev_id,
			next_id = l.next_id,
			predecessors_def = l.prev_number,
			predecessors = @predecessors
		from sdocs_mfr_opers x		
			join (
				select 
					oper_id,
					prev_id = lag(oper_id, 1, null) over (partition by mfr_doc_id, content_id order by number),
					prev_number = lag(number, 1, null) over (partition by mfr_doc_id, content_id order by number),
					next_id = lead(oper_id, 1, null) over (partition by mfr_doc_id, content_id order by number)
				from sdocs_mfr_opers oo
					join #icl_items c on c.id = oo.content_id
			) l on l.oper_id = x.oper_id

		update x
		set @is_first = case when l.prev_id is null then 1 end,
			is_first = @is_first
		from sdocs_mfr_opers x		
			join (
				select 
					oper_id,
					prev_id = lag(oper_id, 1, null) over (partition by mfr_doc_id, content_id order by number)
				from sdocs_mfr_opers
					join #icl_items c on c.id = sdocs_mfr_opers.content_id
				where work_type_id != 4 -- кроме "Конструирование"
			) l on l.oper_id = x.oper_id

		if @skip_links = 1
		begin
			exec tracer_log @tid, '* skip links (calc only is_first, is_last, predecessors)'
			goto final
		end

	BEGIN TRY
	-- BEGIN TRANSACTION

		-- check predecessors
			if @content_id is not null
			begin
				update x set predecessors = null
				from sdocs_mfr_opers x
				where x.content_id = @content_id
					and isnull(x.predecessors,'') != ''
					and not exists(
						select 1 from sdocs_mfr_opers o
							cross apply dbo.str2rows(x.predecessors, ';') p
						where o.content_id = x.content_id and p.item = o.number
						)
			end

		-- clear links
			delete x from sdocs_mfr_opers_links x
			where exists(select 1 from #icl_items where id = x.content_id)

		exec tracer_log @tid, 'связь: все операции детали --> первая операция родителя'
			create table #icl_next(oper_id int, next_id int, parent_content_id int, primary key (oper_id, next_id))

                insert into #icl_next(oper_id, next_id, parent_content_id)
                select xx.oper_id, x.oper_id, max(x.content_id)
                from sdocs_mfr_opers x		
                    join #icl_items i on i.id = x.content_id
                    join sdocs_mfr_contents c on c.content_id = x.content_id
                        join sdocs_mfr_contents c2 on c2.mfr_doc_id = c.mfr_doc_id and c2.parent_id = c.child_id -- дочерняя деталь
                            join sdocs_mfr_opers xx on xx.content_id = c2.content_id -- все дочерние операции
                where x.is_first = 1 -- первая операция родителя
                    and xx.is_last = 1
                group by xx.oper_id, x.oper_id

			-- sdocs_mfr_opers_links
				insert into sdocs_mfr_opers_links(mfr_doc_id, content_id, source_id, target_id, is_input)
				select x.mfr_doc_id, n.parent_content_id, x.oper_id, n.next_id, 1
				from sdocs_mfr_opers x
					join #icl_next n on n.oper_id = x.oper_id

			exec drop_temp_table '#icl_next'

		exec tracer_log @tid, 'связь: последовательные операции внутри детали (по-умолчанию)'
			create table #icl_manual(content_id int primary key)
				insert into #icl_manual(content_id) select distinct x.content_id
				from sdocs_mfr_opers x
					join #icl_items c on c.id = x.content_id
				where isnull(x.predecessors,'') != isnull(x.predecessors_def,'')

			insert into sdocs_mfr_opers_links(mfr_doc_id, content_id, source_id, target_id)
			select x.mfr_doc_id, x.content_id, x.oper_id, x.next_id
			from sdocs_mfr_opers x
				join #icl_items c on c.id = x.content_id
				left join #icl_manual m on m.content_id = x.content_id
			where x.next_id is not null
				and m.content_id is null

		exec tracer_log @tid, 'связь: предшественники заданы вручную'
			exec tracer_log @tid, @tid_msg
			insert into sdocs_mfr_opers_links(mfr_doc_id, content_id, source_id, target_id)
			select x.mfr_doc_id, x.content_id, xx.oper_id, x.oper_id
			from sdocs_mfr_opers x
				join #icl_manual m on m.content_id = x.content_id
				cross apply dbo.str2rows(x.predecessors, ';') p
				join sdocs_mfr_opers xx on xx.mfr_doc_id = x.mfr_doc_id and xx.content_id = x.content_id and xx.number = p.item

		exec tracer_log @tid, 'связь: если предшественник не указан, то копируем предшественников первой операции (кроме КР)'
			create table #icl_noprev(
				oper_id int primary key,
				mfr_doc_id int,
				content_id int,
				first_oper_id int,
				index ix_join(content_id, first_oper_id)
				)
				insert into #icl_noprev(oper_id, mfr_doc_id, content_id)
				select x.oper_id, x.mfr_doc_id, x.content_id
				from sdocs_mfr_opers x
					join #icl_docs i on i.id = x.mfr_doc_id
				where isnull(x.is_first,0) != 1
					and x.predecessors is null

			if exists(select 1 from #icl_noprev)
			begin
				update x set first_oper_id = o.oper_id
				from #icl_noprev x
					join sdocs_mfr_opers o on o.content_id = x.content_id and o.is_first = 1

				insert into sdocs_mfr_opers_links(mfr_doc_id, content_id, source_id, target_id)
				select distinct x.mfr_doc_id, x.content_id, xl.source_id, x.oper_id
				from #icl_noprev x
					join sdocs_mfr_opers_links xl on xl.content_id = x.content_id and xl.target_id = x.first_oper_id
				where not exists(select 1 from sdocs_mfr_opers_links where mfr_doc_id = x.mfr_doc_id and source_id = xl.source_id and target_id = x.oper_id)
			end

        -- дополнительные связи
            -- delete unused
            delete x from sdocs_mfr_opers_links_extra x
                join #icl_docs i on i.id = x.mfr_doc_id
            where x.is_deleted = 1

            -- remove links
            delete x from sdocs_mfr_opers_links x
                join #icl_docs i on i.id = x.mfr_doc_id
                join sdocs_mfr_opers os on os.oper_id = x.source_id
                join sdocs_mfr_opers ot on ot.oper_id = x.target_id
                join sdocs_mfr_opers_links_extra e on 
                        e.mfr_doc_id = x.mfr_doc_id
                    and e.source_content_id = os.content_id
                    and e.source_oper_number = os.number
                    and e.target_content_id = ot.content_id
                    and e.target_oper_number = ot.number
            where x.is_input = 1
                and e.exclude = 1 -- remove links

            insert into sdocs_mfr_opers_links(mfr_doc_id, content_id, source_id, target_id)
            select x.mfr_doc_id, x.target_content_id, os.oper_id, ot.oper_id
            from sdocs_mfr_opers_links_extra x
                join #icl_docs i on i.id = x.mfr_doc_id
                join sdocs_mfr_opers os on os.content_id = x.source_content_id and os.number = x.source_oper_number
                join sdocs_mfr_opers ot on ot.content_id = x.target_content_id and ot.number = x.target_oper_number
            where isnull(x.exclude,0) = 0

		-- delete self-reference
			delete x from sdocs_mfr_opers_links x
				join #icl_docs i on i.id = x.mfr_doc_id
			where x.source_id = x.target_id

        -- update next_id: последняя операция детали --> первая операция родительской детали
        update x set next_id = xl.target_id
        from sdocs_mfr_opers x
            join #icl_docs i on i.id = x.mfr_doc_id
            join sdocs_mfr_opers_links xl on xl.source_id = x.oper_id and xl.is_input = 1
        where x.is_last = 1 and x.next_id is null

		-- update calc date
			update x set d_calc_links = getdate()
			from sdocs x
				join #icl_docs i on i.id = x.doc_id

	-- COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		-- IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

	final:
		exec drop_temp_table '#icl_docs,#icl_items,#icl_next,#icl_manual'
		exec tracer_close @tid
		if @trace = 1 exec tracer_view @tid
end
GO
