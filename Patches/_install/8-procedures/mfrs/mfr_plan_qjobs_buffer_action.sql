if object_id('mfr_plan_qjobs_buffer_action') is not null drop proc mfr_plan_qjobs_buffer_action
go
create proc mfr_plan_qjobs_buffer_action
	@mol_id int,
	@action varchar(32),
	@place_id int = null,
	@selected varchar(max) = null,
	@selected_from varchar(max) = null,
	@selected_to varchar(max) = null,
	@selected_date date = null,
	@selected_wk_shift varchar(20) = null,
    @close_as_completed bit = 1,
	@flow_id int = null,
	@queue_id uniqueidentifier = null
as
begin
	set nocount on;

	declare @proc_name varchar(100) = object_name(@@procid)
	
	-- @buffer
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids
		if @queue_id is null
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mco')
		else
			insert into @buffer select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'mco'
	
	-- @jobs
	declare @jobs as app_pkids
		insert into @jobs select distinct q.plan_job_id
		from mfr_plans_jobs_queues q
			join @buffer i on i.id = q.detail_id

	declare @executors as app_pkids, @count_executors int

	BEGIN TRY
	BEGIN TRANSACTION

		if @action = 'Add' begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @jobs = @jobs

			insert into @executors select item from dbo.str2rows(@selected, ',')
			set @count_executors = (select count(*) from @executors)

			delete x from mfr_plans_jobs_executors x
				join @buffer i on i.id = x.detail_id
					join @executors e on e.id = x.mol_id
			where x.d_doc = @selected_date

			insert into mfr_plans_jobs_executors(detail_id, mol_id, d_doc, plan_duration_wk, plan_duration_wk_id, wk_shift)
			select 
				x.id, e.id, 
				isnull(@selected_date, dbo.today() + 1),
				isnull(x.norm_hours / nullif(@count_executors,0), 1),
				2,
				isnull(@selected_wk_shift, '1')
			from v_mfr_plans_qjobs2 x
				join @buffer i on i.id = x.id
				cross join @executors e
		end

		else if @action = 'Assign' begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @jobs = @jobs

			declare @executor_id int = (select top 1 item from dbo.str2rows(@selected, ','))

			if exists(
				select 1 from mfr_plans_jobs_executors x with(nolock) 
					join @buffer i on i.id = x.detail_id
				)
				delete x from mfr_plans_jobs_executors x
					join @buffer i on i.id = x.detail_id
                where x.status_id = 0;

			insert into mfr_plans_jobs_executors(
				detail_id, mol_id, d_doc, plan_duration_wk, plan_duration_wk_id, wk_shift,
				plan_q,
				post_id, rate_price, note
				)
			select 
				x.detail_id,
				@executor_id,
				isnull(@selected_date, dbo.today() + 1),
				coalesce(e.duration_wk * x.plan_q, x.norm_hours, 1),
				2,
				isnull(@selected_wk_shift, '1'),
				(x.plan_q - isnull(x.fact_q,0)),
				e.post_id, e.rate_price, e.note
			from mfr_plans_jobs_queues x with(nolock)
				join @buffer i on i.id = x.detail_id
				left join mfr_drafts_opers o with(nolock) on o.draft_id = x.draft_id and o.number = x.oper_number
					left join (
						select oper_id, duration_wk = max(duration_wk), duration_wk_id = max(duration_wk_id),
							post_id = max(post_id), rate_price = max(rate_price), note = max(note)
						from mfr_drafts_opers_executors with(nolock)
						group by oper_id
					) e on e.oper_id = o.oper_id
            where exists(select 1 from mfr_plans_jobs_details where id = x.detail_id)
		end

		else if @action = 'Remove' begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @jobs = @jobs
			
			delete x from mfr_plans_jobs_executors x
				join @buffer i on i.id = x.detail_id
			where x.mol_id in (select item from dbo.str2rows(@selected, ','))
		end

		else if @action = 'Exchange' begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @jobs = @jobs

			declare @works table(detail_id int, work_hours float)
				insert into @works(detail_id, work_hours)
				select x.detail_id, plan_duration_wk - isnull(duration_wk,0)
				from mfr_plans_jobs_executors x
					join @buffer i on i.id = x.detail_id
				where x.mol_id in (select item from dbo.str2rows(@selected_from, ','))

			-- remove
			delete x from mfr_plans_jobs_executors x
				join @buffer i on i.id = x.detail_id
			where x.mol_id in (select item from dbo.str2rows(@selected_from, ','))
				and isnull(x.duration_wk,0) = 0

			-- update
			update x set plan_duration_wk = duration_wk
			from mfr_plans_jobs_executors x
				join @buffer i on i.id = x.detail_id
			where x.mol_id in (select item from dbo.str2rows(@selected_from, ','))
				and isnull(x.duration_wk,0) > 0

			insert into @executors select item from dbo.str2rows(@selected_to, ',')
			set @count_executors = (select count(*) from @executors)

			-- ... and insert
			insert into mfr_plans_jobs_executors(detail_id, mol_id, plan_duration_wk, plan_duration_wk_id)
			select 
				x.detail_id, e.id, 
				isnull(x.work_hours / nullif(@count_executors,0), 1),
				2
			from @works x
				join @buffer i on i.id = x.detail_id
				cross join @executors e
		end

		else if @action = 'CloseRows' begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action, @jobs = @jobs

			-- mark as completed/uncompleted
			update x set 
				duration_wk = case when @close_as_completed = 1 then isnull(duration_wk, plan_duration_wk) end,
				duration_wk_id = isnull(duration_wk_id, plan_duration_wk_id),
				fact_q = 
                    case when @close_as_completed = 1 then isnull(nullif(fact_q,0), plan_q)
                    else 0 end,
                status_id = case when @close_as_completed = 1 then 10 else -1 end
			from mfr_plans_jobs_executors x
				join @buffer i on i.id = x.detail_id
            where x.status_id >= 0;

			if @close_as_completed = 1 begin
                update x set
                    fact_q = e.fact_q,
                    fact_defect_q = 0,
                    update_mol_id = @mol_id, update_date = getdate()
                from mfr_plans_jobs_details x
                    join @buffer i on i.id = x.id
                    join (
                        select detail_id, sum(fact_q) as fact_q
                        from mfr_plans_jobs_executors
                        group by detail_id
                    ) e on e.detail_id = x.id

                -- calc queue
                exec mfr_plan_qjobs_calc_queue @details = @buffer
            end
		end

		else if @action = 'CloseJobs' begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action, @jobs = @jobs

			if @queue_id is not null begin
				delete from queues_objs where queue_id = @queue_id and obj_type = 'mfj'
				
				insert into queues_objs(queue_id, obj_type, obj_id)
				select @queue_id, 'mfj', id from @jobs
			end
			else begin
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfj'
				
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'mfj', id, 0 from @jobs
			end

			-- set d_closed
			update mfr_plans_jobs set 
				d_closed = isnull(@selected_date, cast(getdate() as date))
			where plan_job_id in (select id from @jobs)

			-- close jobs
			exec mfr_plan_jobs_buffer_action @mol_id = @mol_id, @action ='BindStatus', @status_id = 100, @queue_id = @queue_id
			
            -- calc queue
			exec mfr_plan_qjobs_calc_queue @details = @buffer
		end

		else if @action = 'RemoveJobsDetails' begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action, @jobs = @jobs

			declare @checked app_pkids
				insert into @checked select detail_id 
				from mfr_plans_jobs_queues x
					join @buffer i on i.id = x.detail_id
				where executors_names is null

			-- mfr_r_plans_jobs_items
			update x set job_id = null, job_detail_id = null, job_status_id = null, job_date = null
			from mfr_r_plans_jobs_items x
				join @checked i on i.id = x.job_detail_id

			-- queues
			delete x from mfr_plans_jobs_queues x
				join @checked i on i.id = x.detail_id

			-- jobs_details
			delete x from mfr_plans_jobs_details x
				join @checked i on i.id = x.id

			-- jobs
			delete x from mfr_plans_jobs x
				join @jobs j on j.id = x.plan_job_id
			where not exists(select 1 from mfr_plans_jobs_details where plan_job_id = x.plan_job_id)
		end

		else if @action = 'SyncJobsBuffer' begin
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'MFJ'
			
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select distinct @buffer_id, 'MFJ', x.PLAN_JOB_ID, @mol_id
			from v_mfr_plans_qjobs2 x
				join @buffer i on i.id = x.id
		end

		else if @action = 'BindFlow' begin
			
			update x set flow_id = @flow_id
			from mfr_plans_jobs_details x
				join @buffer i on i.id = x.id
		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION
end
go
