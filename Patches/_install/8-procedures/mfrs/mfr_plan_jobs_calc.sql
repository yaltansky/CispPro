if object_id('mfr_plan_jobs_calc') is not null drop proc mfr_plan_jobs_calc
go
create proc mfr_plan_jobs_calc
	@mol_id int = null,
	@items app_pkids readonly,
	@queue_id uniqueidentifier = null
as
begin
	set nocount on;
	
	-- buffer
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
		delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'P'

		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'P', id, @mol_id
		from @items

		declare @thread_id varchar(32) = (select thread_id from queues where queue_id = @queue_id)

	-- append
		declare @qid uniqueidentifier = newid()
		exec queue_append
			@queue_id = @qid,
			@mol_id = @mol_id,
			@thread_id = @thread_id,
			@name = 'Пересчёт сменных заданий (буфер)',
			@sql_cmd = 'RMQ.mfr_plan_jobs_calc_items',
			@use_rmq = 1

	-- parent_id
		update queues set parent_id = (select id from queues where queue_id = @queue_id)
		where queue_id = @qid
end
go
-- helper: get data
create proc mfr_plan_jobs_calc;2
	@queue_id uniqueidentifier = null,
    @archive_date date = null,
    @filter_items bit = 0,
	@debug bit = 0
as
begin
    set nocount on;
    
    declare @calc_archive bit = 0

    exec mfr_plan_jobs_calc;10 -- prepare

    -- #fifo
        CREATE TABLE #FIFO(
            PLAN_ID INT,
            MFR_DOC_ID INT,
            SORT_NUMBER INT,
            CONTENT_ID INT,
            ITEM_ID INT,
            OPER_ID INT,
            OPER_NUMBER INT,
            D_DOC DATE,
            JOB_ID INT,
            JOB_DETAIL_ID INT,
            JOB_STATUS_ID INT,
            PLAN_Q FLOAT,
            FACT_Q FLOAT,
            INDEX IX_SORT(ITEM_ID, OPER_NUMBER, SORT_NUMBER, D_DOC, CONTENT_ID)
            )
	-- #docs
		create table #docs(id int primary key)
		if @archive_date is null
		begin
			if not exists(select 1 from mfr_r_plans_jobs_items_archive)
			begin
				set @archive_date = '1900-01-01'
				insert into #docs select doc_id from mfr_sdocs where status_id >= 0
			end
			else begin
				set @archive_date = (select top 1 archive_date from mfr_r_plans_jobs_items_archive)
				insert into #docs select doc_id from mfr_sdocs where status_id >= 0 
                    and isnull(d_issue, @archive_date) >= @archive_date
			end
		end
		
		else begin
			set @calc_archive = 1
			insert into #docs select doc_id from mfr_sdocs where status_id >= 0 and d_issue < @archive_date
			if object_id('mfr_r_plans_jobs_items_archive') is not null 
                truncate table mfr_r_plans_jobs_items_archive
		end
    -- #items
		create table #items(id int primary key)
        insert into #items exec mfr_plan_jobs_calc;90 @queue_id = @queue_id

		if @debug = 0
		begin
			if @filter_items = 1
				delete x from mfr_r_plans_jobs_items x
					join #items i on i.id = x.item_id
			else
				truncate table mfr_r_plans_jobs_items
		end        
	-- /*** DEBUG ***/
        -- DELETE FROM #ITEMS; INSERT INTO #ITEMS SELECT 243049
		-- SET @FILTER_ITEMS = 1
    -- jobs
        insert into #fifo(sort_number, plan_id, mfr_doc_id, job_id, job_detail_id, job_status_id, content_id, item_id, oper_number, d_doc, fact_q)
        select 
            sort_number, plan_id, mfr_doc_id, job_id, job_detail_id, job_status_id, content_id, item_id, oper_number, 
            isnull(d_closed, d_doc),
            value_q
        from v_mfr_fifo_jobs x
        where (@filter_items = 0 or item_id in (select id from #items))
            and (
                (@calc_archive = 1 and (x.d_closed < @archive_date))
                or (@calc_archive = 0 and isnull(x.d_closed, @archive_date) >= @archive_date)
            )
            and value_q > 0
    -- jobs (arvhive)
        insert into #fifo(sort_number, plan_id, mfr_doc_id, job_id, job_detail_id, job_status_id, content_id, item_id, oper_number, d_doc, fact_q)
        select 
            case when x.job_status_id = 100 then -1 else 0 end,
            plan_id, mfr_doc_id, job_id, job_detail_id, job_status_id, content_id, item_id, oper_number, job_date, fact_q
        from mfr_r_plans_jobs_items_archive x
        where x.archive = 0
            and (@filter_items = 0 or item_id in (select id from #items))
            and x.fact_q > 0
    -- products + items
        insert into #fifo(sort_number, plan_id, mfr_doc_id, content_id, item_id, oper_id, oper_number, d_doc, plan_q)
        select x.sort_number, x.plan_id, x.mfr_doc_id, x.content_id, x.item_id, x.oper_id, x.oper_number, x.d_from, x.plan_q
        from v_mfr_fifo_opers x
            join #docs i on i.id = x.mfr_doc_id
        where (@filter_items = 0 or x.item_id in (select id from #items))
            and x.plan_q > 0
    -- products + items (archive)
        insert into #fifo(sort_number, plan_id, mfr_doc_id, content_id, item_id, oper_id, oper_number, d_doc, plan_q)
        select mfr.priority_final, x.plan_id, x.mfr_doc_id, x.content_id, x.item_id, x.oper_id, x.oper_number, 
            x.oper_date, x.plan_q
        from mfr_r_plans_jobs_items_archive x
            join #docs i on i.id = x.mfr_doc_id
            join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id
        where x.archive = 0
            and (@filter_items = 0 or x.item_id in (select id from #items))
            and x.plan_q > 0
	-- final 
        if @debug = 1
            -- select plan_q = sum(plan_q), fact_q = sum(fact_q), r_count = count(*) from #fifo
            select * from #fifo where content_id = 2709 and oper_number = 4
        else 
            SELECT *, LEFT_Q = ISNULL(PLAN_Q, FACT_Q)
            FROM #FIFO
            ORDER BY ITEM_ID, OPER_NUMBER, SORT_NUMBER, D_DOC, CONTENT_ID

	exec drop_temp_table '#fifo,#docs,#products,#items'
end
go
-- helper: prepare
create proc mfr_plan_jobs_calc;10 
as 
begin
	set nocount on;

	IF OBJECT_ID('MFR_R_PLANS_JOBS_ITEMS_ARCHIVE') IS NULL
		SELECT TOP 0 *, 
			ARCHIVE = CAST(0 AS BIT),
			ARCHIVE_DATE = CAST(NULL AS DATE),
			ARCHIVE_USER = CAST(NULL AS INT)
		INTO MFR_R_PLANS_JOBS_ITEMS_ARCHIVE
		FROM MFR_R_PLANS_JOBS_ITEMS
end
go
-- helper: apply @queue_id
create proc mfr_plan_jobs_calc;90
	@queue_id uniqueidentifier
as
begin
	declare @items app_pkids

	if exists(select 1 from queues_objs where queue_id = @queue_id and obj_type = 'MFC')
	begin
		delete from queues_objs where queue_id = @queue_id and obj_type = 'P'
		
		insert into queues_objs(queue_id, obj_type, obj_id)
		select distinct @queue_id, 'P', item_id from sdocs_mfr_contents c
			join queues_objs q on q.obj_id = c.content_id
		where queue_id = @queue_id and q.obj_type = 'MFC'
	end
	
    insert into @items select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'p'
	select id from @items
end
go
-- helper: calc statuses
create proc mfr_plan_jobs_calc;100
	@queue_id uniqueidentifier = null,
    @archive_date date = null,
    @filter_items bit = 0,
	@tid int = 0
as
begin
	set nocount on;

    declare @mol_id int = (select mol_id from queues where queue_id = @queue_id)

	-- #jcalc_items
		create table #jcalc_items(id int primary key)
		insert into #jcalc_items exec mfr_plan_jobs_calc;90 @queue_id = @queue_id

	-- /*** DEBUG ***/
        -- DELETE FROM #JCALC_ITEMS; INSERT INTO #JCALC_ITEMS SELECT 243049
		-- SET @FILTER_ITEMS = 1

	-- #jcalc_docs
        if @archive_date is not null set @queue_id = null
        declare @calc_archive bit = case when @archive_date is not null then 1 end

		create table #jcalc_docs(id int primary key)
		insert into #jcalc_docs select distinct mfr_doc_id from mfr_r_plans_jobs_items
		where mfr_doc_id is not null
            and (@filter_items = 0 or item_id in (select id from #jcalc_items))

	exec tracer_log @tid, 'insert rows with 100%'
		declare @real_archive_date date = 
			case 
				when not exists(select 1 from mfr_r_plans_jobs_items_archive)
					then '1900-01-01'
				else
					(select top 1 archive_date from mfr_r_plans_jobs_items_archive)	
			end

		delete from  mfr_r_plans_jobs_items where slice = '100%'
			and (@filter_items = 0 or item_id in (select id from #jcalc_items))

		insert into mfr_r_plans_jobs_items(
			plan_id, mfr_doc_id, content_id, item_id, oper_id, oper_date, oper_number,
			job_status_id, plan_q, fact_q, slice
			)
		select
			c.plan_id, x.mfr_doc_id, x.content_id, c.item_id, x.oper_id, x.d_to, x.number,
			100, plan_q, plan_q, '100%'
		from sdocs_mfr_opers x with(nolock)
			join mfr_sdocs mfr with (nolock) on mfr.doc_id = x.mfr_doc_id
			join sdocs_mfr_contents c with (nolock) on c.content_id = x.content_id
		where x.mfr_doc_id in (select id from #jcalc_docs)
			and (
				(@archive_date is not null and mfr.d_issue < @archive_date)
				or (mfr.status_id >= 0 and isnull(mfr.d_issue, @real_archive_date) >= @real_archive_date)
				)
			and (@filter_items = 0 or c.item_id in (select id from #jcalc_items))
			and isnull(x.work_type_id,1) != 2
			and x.progress = 1
	exec tracer_log @tid, 'calc #jcalc_opers'
        create table #jcalc_opers(
            oper_id int primary key,
            mfr_doc_id int,
            fact_q float,
            d_to_fact date,
            status_id int
            )

		insert into #jcalc_opers(mfr_doc_id, oper_id, fact_q, d_to_fact, status_id)
		select mfr_doc_id, oper_id, fact_q,
			case when status_id = 100 then job_date end,
			status_id
		from (
			select mfr_doc_id, oper_id, fact_q, job_date,
				status_id = case
					when (plan_q - 0.001) <= fact_q then 100
					when last_opened_job_id is not null then 1 -- исполнение
					else 3 -- запрет
				end
			from (
				select 
					x.mfr_doc_id,
					x.oper_id,
					plan_q = sum(x.plan_q), 
					fact_q = sum(case when x.job_status_id = 100 then x.fact_q end),
					job_date = max(x.job_date),
					last_opened_job_id = max(j.plan_job_id)		
				from mfr_r_plans_jobs_items x
					left join (
						select distinct plan_job_id from mfr_plans_jobs where status_id between 0 and 99
					) j on j.plan_job_id = x.job_id		
				where (@filter_items = 0 or item_id in (select id from #jcalc_items))
					and x.oper_id is not null					
				group by x.mfr_doc_id, x.oper_id
				) x
			) x

		-- status_id --> -2 (Исполнение)
		update x set status_id = -2
		from #jcalc_opers x
			join mfr_plans_jobs_queues q on q.oper_id = x.oper_id
		where q.executors_names is not null
			and x.status_id != 100

	EXEC SYS_SET_TRIGGERS 0
		exec tracer_log @tid, 'sync opers'
			update x
			set status_id = o.status_id,
				fact_q = o.fact_q,
				d_to_fact = case when o.status_id = 100 then o.d_to_fact end
			from sdocs_mfr_opers x
				join #jcalc_opers o on o.oper_id = x.oper_id
		exec tracer_log @tid, 'calc status_id for linked opers'
            -- #items_types
                -- исключаем технологические материалы из критерия "Готов к выдаче"
                -- считаем, что тех.материалы всегда "под рукой"
                declare @exclude_types app_pkids
                    insert @exclude_types select id from dbo.mfr_provides_excl_items(1)
                    
                create table #items_types(type_id int primary key)
                    insert into #items_types 
                    select id from (
                        select distinct id = isnull(item_type_id,0) from sdocs_mfr_contents -- TODO ignatov
                        ) x
                    where not exists(select 1 from @exclude_types) or id not in (select id from @exclude_types)

            -- очистить
            update x
            set status_id = 3 -- запрет
            from sdocs_mfr_opers x
                join sdocs_mfr_contents c on c.content_id = x.content_id
            where x.mfr_doc_id in (select id from #jcalc_docs)
                and (@filter_items = 0 or c.item_id in (select id from #jcalc_items))
                and x.status_id = 2 -- готов к выдаче
                and x.is_first = 1

            -- установить
            update x
            set status_id = 2 -- готов к выдаче
            from sdocs_mfr_opers x
                join sdocs_mfr_contents c on c.content_id = x.content_id
            where x.mfr_doc_id in (select id from #jcalc_docs)
                and (@filter_items = 0 or c.item_id in (select id from #jcalc_items))
                and x.status_id = 3
                -- все входящие завершены
                and not exists(
                    select 1 from sdocs_mfr_opers_links l
                        join sdocs_mfr_opers o on o.oper_id = l.source_id
                            join sdocs_mfr_contents c on c.content_id = o.content_id
                                join #items_types it on it.type_id = isnull(c.item_type_id,0)
                    where l.mfr_doc_id in (select id from #jcalc_docs)
                        and target_id = x.oper_id
                        and isnull(o.status_id,0) < 90  -- для деталей 100 = Сделано
                                                        -- для материалов - Приход, ЛЗК, Выдача эквивалентны
                    )
		exec tracer_log @tid, 'calc progress'
            -- производство
                declare @progress float

                update o set
                    @progress = fact_work_hours / plan_work_hours,
                    progress = 
                        case
                            when @progress >= 1.00 then 0.95
                            else @progress
                        end
                from sdocs_mfr_opers o
                    join (
                        select 
                            o.oper_id,
                            plan_work_hours = o.duration_wk * dur.factor / dur_h.factor,
                            fact_work_hours = j.duration_wk_hours
                        from sdocs_mfr_opers o
                            join projects_durations dur on dur.duration_id = o.duration_wk_id
                            join projects_durations dur_h on dur_h.duration_id = 2
                            join (
                                select oper_id, duration_wk_hours = sum(e.duration_wk * dur.factor / dur_h.factor)
                                from mfr_plans_jobs_details jd
                                    join mfr_plans_jobs_executors e on e.detail_id = jd.id
                                        join projects_durations dur on dur.duration_id = e.duration_wk_id
                                        join projects_durations dur_h on dur_h.duration_id = 2
                                    join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id and j.status_id >= 0
                                where e.duration_wk > 0
                                group by oper_id
                            ) j on j.oper_id = o.oper_id
                        where o.work_type_id = 1
                            and o.status_id != 100
                            and o.duration_wk > 0
                        ) x on x.oper_id = o.oper_id
                where plan_work_hours >= 24
            
            -- кооперация
                declare @today date = cast(getdate() as date)
                update o set
                    @progress = fact_duration / plan_duration,
                    progress = 
                        case
                            when @progress >= 1.00 then 0.95
                            else @progress
                        end                    
                from sdocs_mfr_opers o
                    join (
                        select 
                            o.oper_id,
                            plan_duration = o.duration,
                            fact_duration = (
                                select count(*) from calendar where 
                                    [type] = case when isnull(pl.calendar_id, 1) = 1 then 0 else [type] end
                                    and day_date between j.d_doc and @today
                                )
                            -- datediff(day, j.d_doc, @today)
                        from sdocs_mfr_opers o
                            join mfr_plans_jobs_details jd on jd.oper_id = o.oper_id
                                join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id and j.status_id between 0 and 99
                                    join mfr_plans pl on pl.plan_id = j.plan_id
                        where o.work_type_id = 3
                            and o.status_id != 100
                            and j.d_doc < @today
                        ) x on x.oper_id = o.oper_id
                where plan_duration > 0
        -- @docs
			declare @docs app_pkids
			if @filter_items = 1 insert into @docs select distinct mfr_doc_id from #jcalc_opers
			else insert into @docs select id from #jcalc_docs
		exec tracer_log @tid, 'sync contents'
			exec mfr_plan_jobs_calc_statuses @docs = @docs
		exec tracer_log @tid, 'sync milesrones'
			exec mfr_milestones_calc @docs = @docs
		exec tracer_log @tid, 'resolve content_id'
			update x set content_id = null
			from mfr_plans_jobs_details x
                join #jcalc_docs i on i.id = x.mfr_doc_id
			where content_id is not null
				and not exists(select 1 from sdocs_mfr_contents where content_id = x.content_id)
				and (@filter_items = 0 or item_id in (select id from #jcalc_items))
				
			update x set content_id = r.content_id
			from mfr_plans_jobs_details x
                join #jcalc_docs i on i.id = x.mfr_doc_id
				join (
					select job_detail_id, content_id = min(content_id)
					from mfr_r_plans_jobs_items
					where content_id is not null
					group by job_detail_id
				) r on r.job_detail_id = x.id
			where x.content_id is null
				and (@filter_items = 0 or item_id in (select id from #jcalc_items))
		exec tracer_log @tid, 'resolve oper_id'
			update x set oper_id = null
			from mfr_plans_jobs_details x
                join #jcalc_docs i on i.id = x.mfr_doc_id
			where oper_id is not null
				and (@filter_items = 0 or item_id in (select id from #jcalc_items))
				and not exists(select 1 from sdocs_mfr_opers where oper_id = x.oper_id)

			update x set oper_id = r.oper_id
			from mfr_plans_jobs_details x
                join #jcalc_docs i on i.id = x.mfr_doc_id
				join (
					select job_detail_id, oper_id = min(oper_id)
					from mfr_r_plans_jobs_items
					where oper_id is not null
					group by job_detail_id
				) r on r.job_detail_id = x.id
			where x.oper_id is null
				and (@filter_items = 0 or item_id in (select id from #jcalc_items))
	EXEC SYS_SET_TRIGGERS 1
    
    exec tracer_log @tid, 'archive'
		if @calc_archive = 1
		begin
			IF OBJECT_ID('MFR_R_PLANS_JOBS_ITEMS_ARCHIVE') IS NOT NULL DROP TABLE MFR_R_PLANS_JOBS_ITEMS_ARCHIVE
			SELECT *, 
				ARCHIVE = CAST(1 AS BIT),
				ARCHIVE_DATE = @ARCHIVE_DATE,
				ARCHIVE_USER = @MOL_ID
			INTO MFR_R_PLANS_JOBS_ITEMS_ARCHIVE
			FROM MFR_R_PLANS_JOBS_ITEMS
			
			create table #docs_current(id int primary key)
				insert #docs_current select doc_id from mfr_sdocs where isnull(d_issue, @archive_date) >= @archive_date and status_id >= 0

            update x set archive = 0
            from mfr_r_plans_jobs_items_archive x
                join #docs_current a on a.id = x.mfr_doc_id
            where x.slice != '100%'

            update mfr_r_plans_jobs_items_archive set archive = 0
            where mfr_doc_id is null
		end

	final:
		exec drop_temp_table '#jcalc_docs,#jcalc_items,#jcalc_opers'
		if @tid > 0 exec tracer_view @tid
end
go
-- exec mfr_plan_jobs_calc;2 @debug = 1
-- exec mfr_plan_jobs_calc;100 null
