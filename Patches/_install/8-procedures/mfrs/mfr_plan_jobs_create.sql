if object_id('mfr_plan_jobs_create') is not null drop proc mfr_plan_jobs_create
go
-- exec mfr_plan_jobs_create 1000, 'contents', 'CreateJobsInfo', @ignore_uncompleted = 1, @group_by = 'items'
-- exec mfr_plan_jobs_create 1000, 'contents', 'CreateJobs', @ignore_uncompleted = 1, @group_by = 'items'
create proc mfr_plan_jobs_create
	@mol_id int,
	@context varchar(32), -- contents | opers
	@action varchar(32),
	@places varchar(max) = null,
	@d_doc datetime = null,
	@wk_sheet_id int = null,
	@executor_id int = null,
    @autoexpand bit = 0,
	@work_type_id int = null,
	@agent_id int = null,
	@ignore_uncompleted bit = 0,
	@group_by varchar(30) = null, -- merge, places, items
	@queue_id uniqueidentifier = null
as
begin

  	set nocount on;
		
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')

	create table #jobs_details(
		place_id int, prev_place_id int, place_to_id int,
		mfr_doc_id int, product_id int, parent_item_id int, item_id int,
		group_parent_item_id int, group_item_id int,
		content_id int,
		oper_id int primary key,
		oper_number int, oper_name varchar(100), oper_key varchar(20), resource_id int,
		left_q float,
		duration_wk float, duration_wk_id int,
		index ix_join (place_id, group_parent_item_id, group_item_id)
		)

	if @action = 'CreateJobsInfo'
	begin
		set transaction isolation level read uncommitted;

		exec mfr_items_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

		-- #jobs_details
			exec mfr_plan_jobs_create;2 
				@mol_id = @mol_id,
                @context = @context,
                @places = @places,
				@ignore_uncompleted = @ignore_uncompleted,
				@work_type_id = @work_type_id,
				@group_by = @group_by			

		-- info
			declare @limitDays int = isnull(cast(dbo.app_registry_value('MfrCreateJobsInfoLimitDays') as int), 7)
            select 
                isAdmin = cast(1 as bit), -- dbo.isinrole(@mol_id, 'Admin,Mfr.Admin'),
                limitDays = @limitDays,
				places = isnull(
					dbo.xml2json((
						SELECT PLACE_ID, NAME, NOTE FROM MFR_PLACES
						where place_id in (select distinct place_id from #jobs_details)
						for xml raw
						))
					, ''),
				countJobs = (
					select count(*) from (
						select distinct place_id, place_to_id, group_item_id
						from #jobs_details
					) x
				)
	end

	else if @action = 'CreateJobs' 
	begin
		exec mfr_items_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

		exec mfr_plan_jobs_create;10
			@mol_id = @mol_id,
            @context = @context,
			@d_doc = @d_doc,
			@places = @places,
            @wk_sheet_id = @wk_sheet_id,
            @executor_id = @executor_id,
			@autoexpand = @autoexpand,
			@ignore_uncompleted = @ignore_uncompleted,
			@work_type_id = @work_type_id,
			@agent_id = @agent_id,
			@group_by = @group_by,
			@queue_id = @queue_id
	end
	
	-- else if @action = 'CreateInventory'
	-- begin
	-- 	declare @check_action varchar(32) = 'CheckAccess'
	-- 	exec mfr_items_buffer_action @mol_id = @mol_id, @action = @check_action
			
	-- 	exec mfr_plan_jobs_create;11
	-- 		@mol_id = @mol_id,
	-- 		@group_by = @group_by,
	-- 		@queue_id = @queue_id
	-- end

	exec drop_temp_table '#jobs_details'
end
go
-- helper: get rows
create proc mfr_plan_jobs_create;2
	@mol_id int,
    @context varchar(32), -- contents | opers
	@places varchar(max) = null,
	@autoexpand bit = 0,
	@ignore_uncompleted bit = 0,
	@work_type_id int = null,
	@group_by varchar(32) = null,
	@queue_id uniqueidentifier = null	
as
begin
	-- @contents, @opers
		declare 
            @filter_by varchar(20),
            @contents as app_pkids,
		    @opers as app_pkids

		if @context = 'contents'
        begin
            if @queue_id is not null 
                insert into @contents select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfc'
            else
                insert into @contents select id from dbo.objs_buffer(@mol_id, 'mfc')
		end

        else begin
			if @queue_id is not null 
			    insert into @opers select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfo'
			else
                insert into @opers select id from dbo.objs_buffer(@mol_id, 'mfo')
		end

		if exists(select 1 from @contents)
		begin
			set @filter_by = 'contents'
			delete from @opers

			-- auto-fit @contents
			if @autoexpand = 1
				insert into @contents
				select distinct cc.content_id
				from sdocs_mfr_contents c
					join @contents i on i.id = c.content_id
					join sdocs_mfr_contents cc on cc.mfr_doc_id = c.mfr_doc_id and cc.product_id = c.product_id
						and cc.item_id = c.item_id
				where cc.status_id != 100
					and cc.content_id != c.content_id
					and not exists(select 1 from @contents where id = cc.content_id)
		end
		
		if exists(select 1 from @opers) set @filter_by = 'opers'

    -- #jc_opers
        create table #jc_opers(id int primary key)
        insert into #jc_opers select oper_id from sdocs_mfr_opers
        where (@filter_by = 'contents' and content_id in (select id from @contents))
			or (@filter_by = 'opers' and oper_id in (select id from @opers))

	-- @places_ids
		declare @places_ids app_pkids
		insert into @places_ids select distinct item from dbo.str2rows(@places, ',') where item is not null

	-- select
        declare @limitDays int = isnull(cast(dbo.app_registry_value('MfrCreateJobsInfoLimitDays') as int), 7)
        declare @limitDate date = '2100-01-01'
        -- declare @limitDate date = dateadd(d, 
        --     case
        --         when dbo.isinrole(@mol_id, 'Admin,Mfr.Admin') = 1 then 10000
        --         else @limitDays
        --     end,
        --     dbo.today()
        --     )

		insert into #jobs_details(
			place_id, prev_place_id, place_to_id, mfr_doc_id, product_id,
			parent_item_id, item_id, content_id, oper_id, oper_number, oper_key, oper_name, resource_id,
			left_q, duration_wk, duration_wk_id			
			)
		select
			place_id, prev_place_id, place_to_id, mfr_doc_id, product_id,
			parent_item_id, item_id, content_id, oper_id, oper_number, oper_key, oper_name, resource_id,
			left_q, duration_wk, duration_wk_id			
		from (
			select
				x.place_id,
				prev_place_id = yy.place_id,
				place_to_id = case when @group_by = 'items' then xx.place_id end,
				x.mfr_doc_id,
				x.product_id,
				parent_item_id = c2.item_id,
				c.item_id,
				x.content_id,
				x.oper_id, 
				oper_number = x.number,
				oper_name = x.name,
				oper_key = x.operkey,
				x.resource_id,
				left_q = j.plan_q - isnull(j.fact_q,0),
				x.duration_wk,
				x.duration_wk_id,
				slice =
					case 
						when isnull(x.status_id,0) = 100 then 'completed'
						when x.status_id = 2 then 'ok' -- можно выдавать СЗ
						when @ignore_uncompleted = 1 then 'ok'
						else 'undefined'
					end			
			from (
				select oper_id, plan_q = sum(plan_q), fact_q = sum(fact_q)
				from mfr_r_plans_jobs_items r with(nolock)
                    join #jc_opers i on i.id = r.oper_id
				group by oper_id
				) j
                join sdocs_mfr_opers x with(nolock) on x.oper_id = j.oper_id
				join sdocs_mfr_contents c with(nolock) on c.content_id = x.content_id
					left join sdocs_mfr_contents c2 with(nolock) on c2.mfr_doc_id = c.mfr_doc_id and c2.child_id = c.parent_id
				left join sdocs_mfr_opers xx with(nolock) on xx.oper_id = x.next_id
				left join sdocs_mfr_opers yy with(nolock) on yy.oper_id = x.prev_id
			where isnull(x.status_id,0) != 10 -- not locked
				and isnull(x.work_type_id, 1) = isnull(@work_type_id, 1)
				and (isnull(@places,'') = '' or x.place_id in (select id from @places_ids))
				and j.plan_q > isnull(j.fact_q,0)
                and isnull(x.d_from_plan, @limitDate) <= @limitDate
			) x
		where slice = 'ok'

	-- groups
		update #jobs_details set 
			group_parent_item_id = case when @group_by = 'items' then parent_item_id else 0 end,
			group_item_id = case when @group_by = 'items' then item_id else 0 end

	-- place_to_id
		update j set place_to_id = jj.place_to_id
		from #jobs_details j
			join (
				select x.place_id, x.group_parent_item_id, x.group_item_id, place_to_id = max(x.place_to_id)
				from #jobs_details x
					join (
						select place_id, group_parent_item_id, group_item_id, oper_number = max(oper_number)
						from #jobs_details
						group by place_id, group_parent_item_id, group_item_id
					) xx on xx.place_id = x.place_id 
						and xx.group_parent_item_id = x.group_parent_item_id
						and xx.group_item_id = x.group_item_id
						and xx.oper_number = x.oper_number
				group by x.place_id, x.group_parent_item_id, x.group_item_id
			) jj on jj.place_id = j.place_id 
				and jj.group_parent_item_id = j.group_parent_item_id
				and jj.group_item_id = j.group_item_id
end
GO
-- helper: create jobs
create proc mfr_plan_jobs_create;10
	@mol_id int,
	@context varchar(32), -- contents | opers
    @places varchar(max),
	@d_doc datetime,
	@wk_sheet_id int = null,
	@executor_id int = null,
	@agent_id int = null,
	@work_type_id int = null,
	@autoexpand bit = 0,
	@ignore_uncompleted bit = 0,
	@group_by varchar(30) = '',
	@queue_id uniqueidentifier = null
as
begin
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- trace start
		declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
		declare @tid_msg varchar(max) = concat(@proc_name, '.params:')
		exec tracer_log @tid, @tid_msg		

	declare @plan_id int = (select top 1 plan_id from sdocs_mfr_contents 
		where 
			-- либо детали
			content_id in (select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfc')
			-- либо операции
			or content_id in (
				select content_id from sdocs_mfr_opers
				where oper_id in (select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfo')
			)
		)

	exec tracer_log @tid, 'build #jobs_details'
		exec mfr_plan_jobs_create;2
			@mol_id = @mol_id,
            @context = @context,
            @places = @places,
			@autoexpand = @autoexpand,
			@ignore_uncompleted = @ignore_uncompleted,
			@work_type_id = @work_type_id,
			@group_by = @group_by,
			@queue_id = @queue_id

	-- delete unnecessary slices
		if not exists(select 1 from #jobs_details)
		begin
			print 'warning: источник для создания заданий пуст'
			update queues set note = 'источник для создания заданий пуст' where queue_id = @queue_id
			return
		end

	exec tracer_log @tid, 'set prev_place_id'
		create table #opers(oper_id int primary key)
		insert into #opers select oper_id from #jobs_details

		update x set prev_place_id = prv.place_id
		from #jobs_details x
			join (
				select oper_id = target_id, place_id = min(o.place_id)
				from sdocs_mfr_opers_links l
					join sdocs_mfr_opers o on o.oper_id = l.source_id
					join #opers oo on oo.oper_id = l.target_id
				group by target_id
				having count(distinct o.place_id) = 1
			) prv on prv.oper_id = x.oper_id
		where x.prev_place_id is null

		exec drop_temp_table '#opers'

		set @d_doc = isnull(@d_doc, dbo.today())

	exec tracer_log @tid, 'create jobs'
		declare @jobs table(
			row_id int identity, plan_job_id int, place_id int, place_to_id int, group_item_id int
			)

		insert into @jobs(place_id, place_to_id, group_item_id)
		select distinct place_id, place_to_id, group_item_id
		from #jobs_details
		order by 1, 2, 3

		BEGIN TRY
			BEGIN TRANSACTION
				declare @seed int = isnull((select max(plan_job_id) from mfr_plans_jobs), 0)
				update @jobs set plan_job_id = @seed + row_id

				SET IDENTITY_INSERT MFR_PLANS_JOBS ON
					insert into mfr_plans_jobs(plan_job_id, type_id, plan_id, place_id, d_doc, agent_id, status_id, add_mol_id)
					select
						plan_job_id,
						case 
							when isnull(@work_type_id,1) = 1 then 1 
							else 5
						end,
						@plan_id, place_id, @d_doc, @agent_id, 0, @mol_id
					from @jobs
				SET IDENTITY_INSERT MFR_PLANS_JOBS OFF

				-- lock status
				update x set status_id = 10 -- lock
				from sdocs_mfr_opers x
					join #jobs_details jd on jd.oper_id = x.oper_id
			
				update x set status_id = 10 -- lock
				from sdocs_mfr_contents x
					join #jobs_details jd on jd.content_id = x.content_id

			COMMIT TRANSACTION

			update queues set note = concat('создано заданий: ', @@rowcount) where queue_id = @queue_id

		-- buffer
			declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfj'
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'mfj', plan_job_id, @mol_id from @jobs

			-- auto-folder
			declare @jobsids app_pkids; insert into @jobsids select plan_job_id from @jobs
			exec mfr_plan_jobs_autofolder 1, @jobs = @jobsids
		
		exec tracer_log @tid, 'adjust auto-numbers'
			update x
			set number = concat(s.short_name, '/СЗ-', x.plan_job_id)
			from mfr_plans_jobs x
				join @jobs j on j.plan_job_id = x.plan_job_id
				join mfr_plans pl on pl.plan_id = x.plan_id
					join subjects s on s.subject_id = pl.subject_id

		exec tracer_log @tid, 'create jobs details'
			declare @details app_pkids
			insert into mfr_plans_jobs_details(
				plan_job_id, mfr_doc_id, product_id, prev_place_id, next_place_id,
				parent_item_id, item_id, content_id,
				oper_id, oper_number, oper_key, oper_name, resource_id,
				plan_q, duration_wk, duration_wk_id
				)
				output inserted.id into @details
			select 
				j.plan_job_id, x.mfr_doc_id, x.product_id, x.prev_place_id, x.place_to_id,
				x.parent_item_id, x.item_id, x.content_id,
				x.oper_id, x.oper_number, x.oper_key, x.oper_name, x.resource_id,
				x.left_q, 
				0, -- duration_wk
				2 -- duration_wk_id (часы)
			from #jobs_details x
				join @jobs j 
					on j.place_id = x.place_id 
					and isnull(j.place_to_id,0) = isnull(x.place_to_id,0)
					and j.group_item_id = x.group_item_id

			-- set place_to_id
			update x set place_to_id = jd.next_place_id
			from mfr_plans_jobs x
				join (
					select x.plan_job_id, next_place_id = max(x.next_place_id)
					from mfr_plans_jobs_details x
						join @jobs j on j.plan_job_id = x.plan_job_id
					group by x.plan_job_id
					having count(distinct x.next_place_id) = 1
				) jd on jd.plan_job_id = x.plan_job_id

		    -- norm_duration, norm_duration_wk'
                declare @norm_duration_wk float
                update x set 
                    @norm_duration_wk = x.plan_q * (do.duration_wk * dur2.factor) / dur2h.factor,
                    norm_duration = (do.duration * dur1.factor) / dur1d.factor,
                    norm_duration_wk = @norm_duration_wk,
                    plan_duration_wk = @norm_duration_wk,
                    plan_duration_wk_id = 2
                from mfr_plans_jobs_details x
                    join @jobs j on j.plan_job_id = x.plan_job_id
                    join sdocs_mfr_contents c on c.content_id = x.content_id
                        join mfr_drafts_opers do on do.draft_id = c.draft_id and do.number = x.oper_number
                            left join projects_durations dur1 on dur1.duration_id = do.duration_id
                            left join projects_durations dur2 on dur2.duration_id = do.duration_wk_id
                            join projects_durations dur1d on dur1d.duration_id = 3
                            join projects_durations dur2h on dur2h.duration_id = 2                

        exec tracer_log @tid, 'assign executor (if any)'
            if @executor_id is not null
                insert into mfr_plans_jobs_executors(
                    detail_id, mol_id, name, plan_duration_wk, plan_duration_wk_id, duration_wk, duration_wk_id, note, d_doc, 
                    post_id, plan_q, wk_shift
                    )
                select 
                    x.id, @executor_id, mols.name, x.plan_duration_wk, x.plan_duration_wk_id, x.duration_wk, x.duration_wk_id, x.note, @d_doc, 
                    mols.post_id, x.plan_q, wk.wk_shift
                from mfr_plans_jobs_details x
                    join @details i on i.id = x.id
                    join mols on mols.mol_id = @executor_id
                    join mfr_wk_sheets wk on wk.wk_sheet_id = @wk_sheet_id

		-- auto-queue
			exec mfr_plan_qjobs_calc @details = @details
			
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mco'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'mco', id, @mol_id from @details
			
		exec tracer_log @tid, 'recalc mfr_r_plans_jobs_items (fast & draft)'
			delete x from mfr_r_plans_jobs_items x
				join #jobs_details jd on jd.oper_id = x.oper_id
				
			insert into mfr_r_plans_jobs_items(
				plan_id, mfr_doc_id, content_id, item_id, oper_id, oper_date, oper_number,
				job_id, job_detail_id, job_date, job_status_id,
				plan_q
				)
			select 
				@plan_id, x.mfr_doc_id, x.content_id, x.item_id, x.oper_id, j.d_doc, x.oper_number,
				x.plan_job_id, x.id, j.d_doc, j.status_id,
				x.plan_q
			from mfr_plans_jobs_details x
				join mfr_plans_jobs j on j.plan_job_id = x.plan_job_id
				join @details i on i.id = x.id
	END TRY
	
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH

	-- trace end
		exec tracer_close @tid
end
go
