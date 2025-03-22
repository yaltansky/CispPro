if object_id('mfr_plan_jobs_buffer_action') is not null drop proc mfr_plan_jobs_buffer_action
go
-- exec mfr_plan_jobs_buffer_action 700, 'appendItems'
create proc mfr_plan_jobs_buffer_action
	@mol_id int,
	@action varchar(32),
	@status_id int = null,
	@executor_id int = null,
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	
	declare @buffer as app_pkids
		if @queue_id is null
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfj')
		else
			insert into @buffer select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfj'
	
	declare @plan_job_id int, @task_id int, @dispatch_id int
	declare @err varchar(max)
			
	BEGIN TRY
	BEGIN TRANSACTION

		if @action = 'BindStatus'
		begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @jobs = @buffer

			if @status_id = 101 set @status_id = 100
			
			if @status_id != 100
				update x set status_id = @status_id, update_date = getdate(), update_mol_id = @mol_id
				from mfr_plans_jobs x
					join @buffer i on i.id = x.plan_job_id
			
			else begin
				-- close each job
				declare c_jobs cursor local read_only for select id from @buffer

				open c_jobs; fetch next from c_jobs into @plan_job_id
				BEGIN TRY
					while (@@fetch_status != -1)
					begin
						if (@@fetch_status != -2) 
						begin
							exec mfr_plan_job_sign @mol_id = @mol_id, @plan_job_id = @plan_job_id, @action_id = 'Close'
						end
						fetch next from c_jobs into @plan_job_id
					end
				END TRY

				BEGIN CATCH
					set @err = error_message()
					raiserror (@err, 16, 1)
				END CATCH

				close c_jobs; deallocate c_jobs
			end
		end

		else if @action = 'SendToExecutor'
		begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @jobs = @buffer

			declare @tasks table (task_id int primary key, plan_job_id int index ix_job, dispatch_id int)

			insert into tasks(type_id, author_id, analyzer_id, owner_id, title, status_id, refkey, parent_id)
				output inserted.task_id, inserted.parent_id, inserted.owner_id into @tasks
			select 
				1,
				@mol_id, @mol_id, isnull(pm.mol_id, @executor_id),
				concat('Сменное задание #', x.plan_job_id),
				2, -- исполнение
				x.refkey,
				x.plan_job_id -- temporary map			
			from mfr_plans_jobs x
				join dbo.objs_buffer(@mol_id, 'mfj') i on i.id = x.plan_job_id
				left join (
					select place_id, mol_id = min(mol_id)
					from mfr_places_mols 
					where is_dispatch = 1
					group by place_id
				) pm on pm.place_id = x.place_id

			declare c_tasks cursor local read_only for 
				select plan_job_id, task_id, dispatch_id from @tasks

			open c_tasks; fetch next from c_tasks into @plan_job_id, @task_id, @dispatch_id
				begin try
					while (@@fetch_status != -1)
					begin
						if (@@fetch_status != -2)
						begin
							declare @comment varchar(max) = concat('Прошу принять к исполнению сменное задание #', @plan_job_id, '. Необходимые пометки делайте в примечании строк сменного задания.')

							exec task_sign @task_id = @task_id,
								@action_id = 'Assign',
								@action_name = 'Отправить на исполнение',
								@from_mol_id = @mol_id,
								@to_mols_ids = @dispatch_id,
								@comment = @comment,
								@body = @comment

							update tasks set parent_id = null where task_id = @task_id
						end
						fetch next from c_tasks into @plan_job_id, @task_id, @dispatch_id
					end
				end try 
				begin catch end catch
			close c_tasks; deallocate c_tasks

			update x set status_id = 1, executor_id = t.dispatch_id
			from mfr_plans_jobs x
				join @tasks t on t.plan_job_id = x.plan_job_id
		end

		else if @action = 'SplitByExecutorsDate'
		begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @jobs = @buffer

			declare @details table(
				plan_job_id int,
				mfr_doc_id int,
				product_id int,
				item_id int,
				content_id int,
				oper_id int,
				oper_number int,
				oper_name varchar(50),
				exec_id int index ix_exec,
				d_doc date,
				mol_id int,
				fact_q float,
				index ix_join1 (plan_job_id, d_doc),
				index ix_join2 (plan_job_id, mfr_doc_id, item_id)
				)
			insert into @details(plan_job_id, mfr_doc_id, product_id, item_id, content_id, oper_id, oper_number, oper_name, exec_id, d_doc, mol_id, fact_q)
			select jd.plan_job_id, jd.mfr_doc_id, jd.product_id, jd.item_id, jd.content_id, jd.oper_id, jd.oper_number, jd.oper_name, je.id, je.d_doc, je.mol_id, je.fact_q
			from mfr_plans_jobs_details jd
				join @buffer i on i.id = jd.plan_job_id
				join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
				join mfr_plans_jobs_executors je on je.detail_id = jd.id
			where je.fact_q > 0

			declare @jobs table(
				row_id int identity primary key,
				plan_job_id int index ix_job,
				d_doc date,
				copy_number int,
				new_job_id int
				)
			insert into @jobs(plan_job_id, d_doc)
			select distinct plan_job_id, d_doc from @details

			update x
				set copy_number = xx.copy_number
			from @jobs x
				join (
					select 
						row_id,
						copy_number = row_number() over (partition by plan_job_id order by row_id)
					from @jobs
				) xx on xx.row_id = x.row_id

			declare @seed int = isnull((select max(plan_job_id) from mfr_plans_jobs), 1)
			update @jobs set new_job_id =  @seed + row_id

			SET IDENTITY_INSERT MFR_PLANS_JOBS ON
				insert into mfr_plans_jobs(
					subject_id, plan_id, plan_job_id, place_id, place_to_id, d_doc, d_closed, number, status_id, type_id, slice
					)
				select
					subject_id, plan_id, i.new_job_id, place_id, place_to_id, i.d_doc, i.d_doc, concat(number, '-', i.copy_number), status_id, type_id, slice
				from mfr_plans_jobs x
					join @jobs i on i.plan_job_id = x.plan_job_id
			SET IDENTITY_INSERT MFR_PLANS_JOBS OFF

			insert into mfr_plans_jobs_details(
				plan_job_id, mfr_doc_id, product_id, parent_item_id, parent_item_q, item_id, oper_id, content_id, oper_number, oper_name, prev_place_id, unit_name,
				plan_duration_wk, plan_duration_wk_id, problem_id,  norm_duration, norm_duration_wk, next_place_id,
				add_mol_id
				)
			select 
				j.new_job_id, x.mfr_doc_id, x.product_id, x.parent_item_id, x.parent_item_q, x.item_id, x.oper_id, x.content_id, x.oper_number, x.oper_name, x.prev_place_id, x.unit_name,
				sum(je.plan_duration_wk), max(je.plan_duration_wk_id), x.problem_id, max(x.norm_duration), max(x.norm_duration_wk), max(x.next_place_id),
				@mol_id
			from mfr_plans_jobs_details x
				join @details i on i.plan_job_id = x.plan_job_id
					join @jobs j on j.plan_job_id = x.plan_job_id and j.d_doc = i.d_doc
					join mfr_plans_jobs_executors je on je.id = i.exec_id
			group by 
				j.new_job_id, x.mfr_doc_id, x.product_id, x.parent_item_id, x.parent_item_q, x.item_id, x.oper_id, x.content_id, x.oper_number, x.oper_name, x.prev_place_id, x.unit_name,
				x.problem_id

			insert into mfr_plans_jobs_executors(
				detail_id, mol_id, name, plan_duration_wk, plan_duration_wk_id, duration_wk, duration_wk_id, note, d_doc, overloads_duration_wk, post_id, rate_price, plan_q, fact_q, wk_shift
				)
			select 
				jd.id, x.mol_id, x.name, x.plan_duration_wk, x.plan_duration_wk_id, x.duration_wk, x.duration_wk_id, x.note, x.d_doc, x.overloads_duration_wk, x.post_id, x.rate_price, x.plan_q, x.fact_q, x.wk_shift
			from mfr_plans_jobs_executors x
				join @details i on i.exec_id = x.id
					join @jobs j on j.plan_job_id = i.plan_job_id and j.d_doc = i.d_doc
						join mfr_plans_jobs_details jd on jd.plan_job_id = j.new_job_id and jd.mfr_doc_id = i.mfr_doc_id and jd.item_id = i.item_id

			delete x from mfr_plans_jobs_details x
				join @jobs j on j.new_job_id = x.plan_job_id
			where not exists(select 1 from mfr_plans_jobs_executors where detail_id = x.id)

			update x set plan_q = fact_q 
			from mfr_plans_jobs_details x
				join @jobs j on j.new_job_id = x.plan_job_id

			update mfr_plans_jobs set status_id = -1 
			where plan_job_id in (select plan_job_id from @jobs)

			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'mfj', new_job_id, 0
			from @jobs
		end

		else if @action = 'CalcJobsRegister'
		begin
			exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action

			declare @items as app_pkids; insert into @items select distinct item_id from mfr_plans_jobs_details jd
				join @buffer i on i.id = jd.plan_job_id
			exec mfr_plan_jobs_calc @mol_id = @mol_id, @items = @items, @queue_id = @queue_id
		end

	COMMIT TRANSACTION
	    -- trace end
        exec tracer_close @tid
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

end 
go
