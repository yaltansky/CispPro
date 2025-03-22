if object_id('mfr_opers_calc') is not null drop proc mfr_opers_calc
go
-- exec mfr_opers_calc 1000, @doc_id = 543931, @mode = 2, @trace = 1
-- exec mfr_opers_calc 1000, @doc_id = 2009946, @mode = 20
create proc mfr_opers_calc
	@mol_id int,
	@plan_id int = null,
	@doc_id int = null,
	@docs app_pkids readonly,
	@mode int = null, -- null - all, 1 - циклограмма (базовый план), 2 - прогноз, 3 - ПДО, 20 - сохранить Прогноз в Оперативный план
	@empty_only bit = 0, -- только пустые даты (используется для ПДО)
	@queue_id uniqueidentifier = null,
	@trace bit = 0
as
begin
	set nocount on;

	-- init log
		declare @today datetime = dbo.today()
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @mol_id=', @mol_id,
			' @plan_id=', @plan_id,
			' @doc_id=', @doc_id
			)
		exec tracer_log @tid, @tid_msg
	-- #op_docs
		create table #op_docs(id int primary key)
		
		if @queue_id is not null
			insert into #op_docs select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'mfr'

		else if not exists(select 1 from @docs)
		begin
			if @plan_id is not null
				insert into #op_docs select doc_id from mfr_sdocs where plan_id = @plan_id
					and status_id >= 0
			else
				insert into #op_docs values(@doc_id)
		end
		
		if exists(select 1 from @docs)
		begin
			delete from #op_docs
			insert into #op_docs select id from @docs
		end

		-- для ПДО включаем только те заказы, у которых есть Дата ПДО
		if @mode = 3
		begin
			delete x from #op_docs x 
				join mfr_sdocs mfr on mfr.doc_id = x.id
			where mfr.d_issue_plan is null -- нет даты ПДО
		end

        if @mode = 20
        begin
            EXEC SYS_SET_TRIGGERS 0
                update x set 
                    opers_from_ploper = opers_from_predict,
                    opers_to_ploper = opers_to_predict,
                    duration_buffer_ploper = duration_buffer_predict
                from sdocs_mfr_contents x
                    join #op_docs i on i.id = x.mfr_doc_id
                
                update x set 
                    d_from_ploper = d_from_predict,
                    d_to_ploper = d_to_predict
                from sdocs_mfr_opers x
                    join #op_docs i on i.id = x.mfr_doc_id
            EXEC SYS_SET_TRIGGERS 1
            return
        end

		declare @subject_id int = (select top 1 subject_id from sdocs where doc_id in (select id from #op_docs))
	-- normalize
		EXEC SYS_SET_TRIGGERS 0
			update x set mfr_doc_id = c.mfr_doc_id
			from sdocs_mfr_opers x
				join sdocs_mfr_contents c on c.content_id = x.content_id
					join #op_docs i on i.id = c.mfr_doc_id
			where x.mfr_doc_id != c.mfr_doc_id

			update x set status_id = 0 
			from sdocs_mfr_opers x
				join #op_docs i on i.id = x.mfr_doc_id
			where x.status_id is null
		EXEC SYS_SET_TRIGGERS 1
	-- prepare
		-- opers
			exec tracer_log @tid, '#opers'

			create table #opers(
				oper_id int primary key,
                gantt_id int,
                calc_mode_id int,
                calendar_id int,
				--
				mfr_doc_id int,
				product_id int,
				content_id int index ix_content,
                item_type_id int index ix_item_type,
				--
				duration float,
				d_initial date,				
				d_doc date,				
				d_after datetime,
				d_before datetime,
				d_from datetime,
				d_to datetime,
				d_ship date,
				d_issue_plan date,
				progress float,
                index ix_join1(calc_mode_id, calendar_id)
				)

			create table #op_parents(
				content_id int primary key,
				opers_from date,
				opers_to date,
				duration_buffer int
				)

			insert into #opers(
				oper_id, calc_mode_id, calendar_id,
				content_id, item_type_id, mfr_doc_id, product_id,
				d_initial, d_doc, d_after, d_before, d_from,
				duration, progress
				)
			select 
				o.oper_id, isnull(pl.calc_mode_id, 2), isnull(pl.calendar_id, 1),
				c.content_id, isnull(c.item_type_id, 0), c.mfr_doc_id, c.product_id,
				sd.d_doc,
                c.d_doc,
				o.d_after,
				o.d_before,
				o.d_from, -- базовый план
				case
                    when plc.work_hours is not null then
                        isnull(o.duration,1) *
                        case
                            when dur.factor24 != 1 then 1.0 / plc.work_hours
                            else 1
                        end
                    else 
                        isnull(o.duration,1) * case when isnull(pl.calendar_id,1) = 3 then dur.factor24 else dur.factor end
                end,
				case 
					when c.is_buy = 0 then
						case when o.status_id = 100 then 1 else isnull(o.progress,0) end
					else 
						case when o.status_id >= 30 then 1 else isnull(o.progress,0) end
				end
			from sdocs_mfr_opers o
				join sdocs_mfr_contents c on c.content_id = o.content_id
					join sdocs sd on sd.doc_id = c.mfr_doc_id
						left join mfr_plans pl on pl.plan_id = sd.plan_id
				join projects_durations dur on dur.duration_id = o.duration_id
                left join mfr_places plc on plc.place_id = o.place_id
			where c.mfr_doc_id in (select id from #op_docs)
				and (
						@mode in (1,3) 
						-- условие для прогноза
						or 	(c.status_id < 30 and isnull(o.status_id,0) < 30)	-- для материалов Приход, ЛЗК, Выдано
																				-- считаются выполненными задачами
					)

			if not exists(select 1 from #opers)
			begin
				print 'mfr_opers_calc: нет операций для пересчёта.'
				goto final
			end
        -- gantts
		    exec tracer_log @tid, 'clr_gantts'

            declare @group_id uniqueidentifier = newid()

			insert into clr_gantts(group_id, d_today, calendar_id, calc_mode_id)
            select distinct @group_id, @today, isnull(pl.calendar_id, 1), isnull(pl.calc_mode_id, 2)
            from sdocs sd 
                join mfr_plans pl on pl.plan_id = sd.plan_id
                join #op_docs i on i.id = sd.doc_id

            update x set gantt_id = g.gantt_id
            from #opers x
                join clr_gantts g on g.calc_mode_id = x.calc_mode_id and g.calendar_id = x.calendar_id
            where g.group_id = @group_id
            
            create index ix_join2 on #opers(gantt_id)

            exec tracer_log @tid, 'clr_gantt_tasks'
                insert into clr_gantt_tasks(gantt_id, group_id, task_id, d_initial, d_after, d_before, progress, duration, duration_buffer_max)
                select gantt_id, mfr_doc_id, oper_id, d_initial, d_after, d_before, progress, duration,
                    0 -- default duration_buffer_max
                from #opers x

            exec tracer_log @tid, 'clr_gantt_tasks_links'
			insert into clr_gantt_tasks_links(gantt_id, source_id, target_id)
			select distinct o.gantt_id, x.source_id, x.target_id
			from sdocs_mfr_opers_links x
				join #op_docs i on i.id = x.mfr_doc_id
				join #opers o on o.oper_id = x.source_id
				join #opers o2 on o2.oper_id = x.target_id
    -- process
        begin try
            declare c_gantts cursor local read_only for 
                select gantt_id from clr_gantts where group_id = @group_id
            
            declare @gantt_id int
            
            open c_gantts; fetch next from c_gantts into @gantt_id
                while (@@fetch_status != -1)
                begin
                    if (@@fetch_status != -2) exec mfr_opers_calc;2 @gantt_id, @mode, @empty_only, @tid
                    print concat('gantt #', @gantt_id, ' processed')
                    fetch next from c_gantts into @gantt_id
                end
            close c_gantts; deallocate c_gantts
        end try
        begin catch
            declare @err varchar(max) = error_message()
            raiserror (@err, 16, 1)
            close c_gantts; deallocate c_gantts
            goto final
        end catch
    -- post-process
		exec tracer_log @tid, 'post process'

		-- sync milestones
		declare @ms_docs app_pkids; insert into @ms_docs select id from #op_docs
		exec mfr_milestones_calc @docs = @ms_docs

	final:
		exec drop_temp_table '#op_docs,#opers,#op_parents'

        truncate table clr_gantt_tasks
        truncate table clr_gantt_tasks_links
        delete from clr_gantts

		exec tracer_close @tid
		if @trace = 1 exec tracer_view @tid
end
GO
create proc mfr_opers_calc;2
    @gantt_id int,
    @mode int,
    @empty_only bit,
    @tid int
as
begin

    declare @today datetime = dbo.today()
    declare @trace bit = case when @tid > 0 then 1 else 0 end
    declare @tid_msg varchar(max)

    create table #op_docs_calc(id int primary key)
        insert into #op_docs_calc
        select distinct mfr_doc_id from #opers 
        where gantt_id = @gantt_id

    create table #result(
        task_id int index ix_task,
        d_from datetime,
        d_to datetime,
        duration_buffer int,
        outline_level int,
        duration decimal(18,2),
        progress decimal(18,2),
        is_critical bit
        )

    EXEC SYS_SET_TRIGGERS 0 -- optimize (start)

    -- БАЗОВЫЙ ПЛАН
        declare 
            @count_tasks int, @count_tasks_links int,
            @max_date date = dateadd(y, 1, dbo.today()),
            @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%готовая продукция%')

        if isnull(@mode,1) = 1
        begin
            -- options
                -- Тип расчёта "Позднее начало"
                update clr_gantts set calc_mode_id = 2 where gantt_id = @gantt_id	

                update x set 
                    d_final = isnull(sd.d_ship, @max_date), -- считаем от плановой даты отгрузки
                    progress = 0
                from clr_gantt_tasks x
                    join #opers o on o.oper_id = x.task_id
                        join sdocs sd on sd.doc_id = o.mfr_doc_id
                where x.gantt_id = @gantt_id
            exec tracer_log @tid, 'calc gantt'
                if @trace = 1
                begin
                    set @count_tasks = (select count(*) from clr_gantt_tasks where gantt_id = @gantt_id)
                    set @count_tasks_links = (select count(*) from clr_gantt_tasks_links where gantt_id = @gantt_id)
                    set @tid_msg = concat('*** cyclogram_calc: tasks ', @count_tasks, ', links ', @count_tasks_links)
                    exec tracer_log @tid, @tid_msg
                end

                insert into #result	exec cyclogram_calc @gantt_id = @gantt_id, @trace_allowed = @trace
                
            exec tracer_log @tid, 'update opers (from gantt)', 1
                update x
                set d_from = r.d_from,
                    d_to = r.d_to,
                    duration_buffer = r.duration_buffer
                from sdocs_mfr_opers x
                    join #result r on r.task_id = x.oper_id
            exec tracer_log @tid, 'update contents (from opers)', 1
                -- clear base on items
                    update x
                    set opers_from = null, opers_to = null, duration_buffer = null, opers_days = null
                    from sdocs_mfr_contents x
                        join #op_docs_calc i on i.id = x.mfr_doc_id

                exec tracer_log @tid, 'calc base of items (by opers)', 1
                    update x
                    set opers_from = op.opers_from,
                        opers_to = op.opers_to,
                        duration_buffer = op.duration_buffer,
                        opers_days = datediff(d, op.opers_from, op.opers_to)		
                    from sdocs_mfr_contents x
                        join (
                            select 
                                content_id,
                                min(d_from) as opers_from,
                                max(d_to) as opers_to,
                                min(duration_buffer) as duration_buffer
                            from sdocs_mfr_opers op
                                join #op_docs_calc i on i.id = op.mfr_doc_id
                            group by content_id
                        ) op on op.content_id = x.content_id
                
                exec tracer_log @tid, 'calc parents', 1
                    insert into #op_parents(content_id, opers_from, opers_to, duration_buffer)
                        select
                            r.content_id,
                            min(r2.opers_from) as opers_from,
                            max(r2.opers_to) as opers_to,
                            min(r2.duration_buffer)
                        from sdocs_mfr_contents r
                            join #op_docs_calc i on i.id = r.mfr_doc_id
                            join sdocs_mfr_contents r2 on 
                                    r2.mfr_doc_id = r.mfr_doc_id
                                and	r2.product_id = r.product_id
                                and r2.child_id = r.parent_id
                        where isnull(r.opers_count,0) = 0
                        group by r.content_id

                    declare @d_from datetime, @d_to datetime, @days int
                    update x
                    set @d_from = isnull(x.opers_from, xx.opers_from),
                        @d_to = isnull(x.opers_to, xx.opers_to),
                        @days = datediff(d, @d_from, @d_to),
                        opers_from = @d_from,
                        opers_to = @d_to,
                        opers_days = case when @days = 0 then 1 else @days end,
                        duration_buffer = xx.duration_buffer
                    from sdocs_mfr_contents x
                        join #op_parents xx on xx.content_id = x.content_id

                -- d_issue_calc
                    update x
                    set d_issue_calc = c.opers_to
                    from sdocs x
                        join (
                            select mfr_doc_id, 
                                opers_to = max(isnull(d_to_fact, d_to))
                            from sdocs_mfr_opers
                            where milestone_id = @attr_product
                            group by mfr_doc_id
                        ) c on c.mfr_doc_id = x.doc_id
                        join #op_docs_calc i on i.id = x.doc_id
        end 
    -- ПРОГНОЗ
        if isnull(@mode,2) = 2
        begin
            -- options
                -- Тип расчёта "Ранее начало"
                update clr_gantts set d_today = @today, calc_mode_id = 1 where gantt_id = @gantt_id	

                -- технологические операции считаем завершёнными
                    -- #excl_types
                        create table #excl_types(type_id int primary key)
                        insert into #excl_types select id from dbo.mfr_provides_excl_items(1)

                    update x set 
                        progress = 1,
                        d_initial = isnull(o.d_from_plan, @today),
                        d_to_fact = isnull(o.d_to_plan, @today),
                        duration = 1 -- 1 день
                    from clr_gantt_tasks x
                        join sdocs_mfr_opers o on o.oper_id = x.task_id
                            join sdocs_mfr_contents c on c.content_id = o.content_id
                                join #excl_types it on it.type_id = c.item_type_id
                    where x.gantt_id = @gantt_id

                -- не завершённые операции - от текущей даты
                update x set 
                    d_initial = @today,
                    d_final = null
                from clr_gantt_tasks x
                    join #opers o on o.oper_id = x.task_id
                where x.gantt_id = @gantt_id
            exec tracer_log @tid, 'calc gantt'
                if @trace = 1
                begin
                    set @count_tasks = (select count(*) from clr_gantt_tasks where gantt_id = @gantt_id)
                    set @count_tasks_links = (select count(*) from clr_gantt_tasks_links where gantt_id = @gantt_id)
                    set @tid_msg = concat('*** cyclogram_calc: tasks ', @count_tasks, ', links ', @count_tasks_links)
                    exec tracer_log @tid, @tid_msg
                end

                delete from #result
                insert into #result exec cyclogram_calc @gantt_id, @trace_allowed = @trace
            exec tracer_log @tid, 'update opers (from gantt)', 1
                -- clear
                update x
                set d_from_predict = null, d_to_predict = null, duration_buffer_predict = null
                from sdocs_mfr_opers x
                    join #op_docs_calc i on i.id = x.mfr_doc_id

                update x
                set opers_from_predict = null, opers_to_predict = null, duration_buffer_predict = null
                from sdocs_mfr_contents x
                    join #op_docs_calc i on i.id = x.mfr_doc_id
                
                -- set
                update x
                set d_from_predict = r.d_from,
                    d_to_predict = r.d_to,
                    duration_buffer_predict = r.duration_buffer
                from sdocs_mfr_opers x
                    join #result r on r.task_id = x.oper_id

                -- технологические материалы считаем по ПДО
                update x
                set d_from_predict = isnull(x.d_from_plan, @today),
                    d_to_predict = isnull(x.d_to_plan, @today),
                    duration_buffer_predict = 10
                from sdocs_mfr_opers x
                    join #result r on r.task_id = x.oper_id
                    join sdocs_mfr_contents c on c.content_id = x.content_id
                        join #excl_types it on it.type_id = c.item_type_id

            exec tracer_log @tid, 'update sdocs_mfr_contents(childs)', 1
                update x
                set opers_from_predict = op.opers_from_predict,
                    opers_to_predict = op.opers_to_predict,
                    duration_buffer_predict = op.duration_buffer_predict
                from sdocs_mfr_contents x
                    join (
                        select 
                            content_id,
                            min(d_from_predict) as opers_from_predict,
                            max(d_to_predict) as opers_to_predict,
                            min(duration_buffer_predict) as duration_buffer_predict
                        from sdocs_mfr_opers op
                            join #op_docs_calc i on i.id = op.mfr_doc_id
                        group by content_id
                    ) op on op.content_id = x.content_id
            exec tracer_log @tid, 'update sdocs_mfr_contents(parents)', 1
                insert into #op_parents(content_id, opers_from, opers_to, duration_buffer)
                select
                    r.content_id,
                    min(r2.opers_from_predict),
                    max(r2.opers_to_predict),
                    min(r2.duration_buffer_predict)
                from sdocs_mfr_contents r with(nolock)
                    join #op_docs_calc i on i.id = r.mfr_doc_id
                    join sdocs_mfr_contents r2 with(nolock) on 
                            r2.mfr_doc_id = r.mfr_doc_id
                        and	r2.product_id = r.product_id
                        and r2.parent_id = r.child_id
                where r.has_childs = 1
                    and isnull(r.opers_count,0) = 0 -- если у детали/узла нет операций, то наследуем от дочерних узлов
                    and r2.opers_from_predict is not null
                group by r.content_id

                update x
                set opers_from_predict = xx.opers_from,
                    opers_to_predict = xx.opers_to,
                    duration_buffer_predict = xx.duration_buffer
                from sdocs_mfr_contents x
                    join #op_parents xx on xx.content_id = x.content_id

                update x set
                    opers_from_predict = opers_from, opers_to_predict = opers_to
                from sdocs_mfr_contents x
                    join #op_docs_calc i on i.id = x.mfr_doc_id
                where status_id = 100
                    and (
                        isnull(opers_from_predict,0) != opers_from
                        or isnull(opers_to_predict,0) != opers_to
                    )

                update x set
                    opers_to_predict = opers_to_fact
                from sdocs_mfr_contents x
                    join #op_docs_calc i on i.id = x.mfr_doc_id
                where opers_to_predict != opers_to_fact
                
            -- d_issue_forecast
            update x
            set d_issue_forecast = c.opers_to_predict
            from sdocs x
                join (
                    select mfr_doc_id, 
                        opers_to_predict = max(isnull(d_to_fact, d_to_predict))
                    from sdocs_mfr_opers
                    where milestone_id = @attr_product
                    group by mfr_doc_id
                ) c on c.mfr_doc_id = x.doc_id
                join #op_docs_calc i on i.id = x.doc_id
        end 
    -- ПЛАН ПДО
        if isnull(@mode,3) = 3
        begin
            -- options
                declare @calc_mode_id int = (select calc_mode_id from clr_gantts where gantt_id = @gantt_id)

                -- Раннее начало
                if @calc_mode_id = 1 begin
                    -- ограничения
                    update x set 
                        -- Начальная дата - дата открытия заказа
                        d_initial = sd.d_doc, 

                        -- Ограничение “Начать после” - дата материала из состава изделия (в журнале “Закупки” - это поле “Дата”).
                        d_after = c.d_doc,

                        progress = 0
                    from clr_gantt_tasks x
                        join #opers o on o.oper_id = x.task_id
                            join sdocs sd on sd.doc_id = o.mfr_doc_id
                            join mfr_sdocs_contents c on c.content_id = o.content_id
                    where x.gantt_id = @gantt_id
                end
                
                -- Позднее начало
                else begin
                    -- ограничения
                    update x set 
                        d_final = isnull(sd.d_issue_plan, @max_date), -- считаем от плановой даты выпуска
                        progress = 0
                    from clr_gantt_tasks x
                        join #opers o on o.oper_id = x.task_id
                            join sdocs sd on sd.doc_id = o.mfr_doc_id
                    where x.gantt_id = @gantt_id
                end
            exec tracer_log @tid, 'calc gantt'
                if @trace = 1
                begin
                    set @count_tasks = (select count(*) from clr_gantt_tasks where gantt_id = @gantt_id)
                    set @count_tasks_links = (select count(*) from clr_gantt_tasks_links where gantt_id = @gantt_id)
                    set @tid_msg = concat('*** cyclogram_calc: tasks ', @count_tasks, ', links ', @count_tasks_links)
                    exec tracer_log @tid, @tid_msg
                end

                insert into #result	exec cyclogram_calc @gantt_id = @gantt_id, @trace_allowed = @trace
            exec tracer_log @tid, 'update opers (from gantt)', 1
                update x
                set d_from_plan = r.d_from,
                    d_to_plan = r.d_to
                from sdocs_mfr_opers x
                    join #result r on r.task_id = x.oper_id
                where @empty_only = 0
                    or d_from_plan is null
            exec tracer_log @tid, 'update contents (from opers)', 1
                -- clear base on items
                    update x
                    set opers_from_plan = null, opers_to_plan = null
                    from sdocs_mfr_contents x
                        join #op_docs_calc i on i.id = x.mfr_doc_id

                exec tracer_log @tid, 'calc base of items (by opers)', 1
                    update x
                    set opers_from_plan = cast(op.opers_from_plan as date),
                        opers_to_plan = cast(op.opers_to_plan as date)
                    from sdocs_mfr_contents x
                        join (
                            select 
                                content_id,
                                min(d_from_plan) as opers_from_plan,
                                max(d_to_plan) as opers_to_plan
                            from sdocs_mfr_opers op
                                join #op_docs_calc i on i.id = op.mfr_doc_id
                            group by content_id
                        ) op on op.content_id = x.content_id
                
                exec tracer_log @tid, 'calc parents', 1
                    insert into #op_parents(content_id, opers_from, opers_to)
                        select
                            r.content_id,
                            min(r2.opers_from_plan),
                            max(r2.opers_to_plan)
                        from sdocs_mfr_contents r
                            join #op_docs_calc i on i.id = r.mfr_doc_id
                            join sdocs_mfr_contents r2 on 
                                    r2.mfr_doc_id = r.mfr_doc_id
                                and	r2.product_id = r.product_id
                                and r2.child_id = r.parent_id
                        where isnull(r.opers_count,0) = 0
                        group by r.content_id
                    
                    update x
                    set opers_from_plan = xx.opers_from,
                        opers_to_plan = xx.opers_to
                    from sdocs_mfr_contents x
                        join #op_parents xx on xx.content_id = x.content_id
        end

    EXEC SYS_SET_TRIGGERS 1 -- optimize (end)        

    exec drop_temp_table '#op_docs_calc,#result'
end
GO

-- exec mfr_opers_calc 1000, @doc_id = 644666, @mode = 2
