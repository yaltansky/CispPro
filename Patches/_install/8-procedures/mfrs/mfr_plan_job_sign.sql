if object_id('mfr_plan_job_sign') is not null drop proc mfr_plan_job_sign
go
create proc mfr_plan_job_sign
	@mol_id int,
	@plan_job_id int = null,
	@task_id int = null,
	@action_id varchar(32),
	@queue_id uniqueidentifier = null
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @type_id int, @status_id int, @author_id int
	declare @refkey varchar(250)

	if @task_id is not null
	begin
		select 
			@type_id = type_id,
			@status_id = status_id,
			@refkey = refkey,
			@author_id = author_id
		from tasks where task_id = @task_id
		
		set @plan_job_id = dbo.strtoken(@refkey, '/', 6)
	end

	BEGIN TRY
		exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any', @job_id = @plan_job_id

		if @action_id in ('Send')
			update mfr_plans_jobs set status_id = 0
			where plan_job_id = @plan_job_id

		if @action_id in ('Assign')
		begin
			declare @executor_id int = (select top 1 mol_id from tasks_mols where task_id = @task_id and role_id = 1 and mol_id <> @author_id)
			update mfr_plans_jobs set status_id = 1, executor_id = @executor_id
			where plan_job_id = @plan_job_id
				and status_id = 0
		end
		
		if @action_id in ('Redirect')
		begin
			update mfr_plans_jobs set 
				status_id = 1,
				executor_id = (select analyzer_id from tasks where task_id = @task_id)
			where plan_job_id = @plan_job_id
		end

		if @action_id in ('AcceptToExecute')
			update mfr_plans_jobs set status_id = 2
			where plan_job_id = @plan_job_id
			
		if @action_id in ('PassToAcceptance')
		begin
			exec mfr_plan_job_sign;2 @mol_id, @plan_job_id, @task_id

			if not exists(select 1 from mfr_plans_jobs_details where plan_job_id = @plan_job_id and isnull(fact_q,0) <> plan_q)
				set @action_id = 'Close'
			else begin
				update mfr_plans_jobs set status_id = 10
				where plan_job_id = @plan_job_id

				update tasks set status_id = 4 where task_id = @task_id
			end
		end

		if @action_id in ('Revoke') 
		begin
			exec mfr_plan_job_sign;2 @mol_id, @plan_job_id, @task_id
			update mfr_plans_jobs set status_id = -2 where plan_job_id = @plan_job_id	
			update tasks set status_id = 5 where task_id = @task_id
		end

		if @action_id in ('Close') 
		begin
			if not exists(select 1 from mfr_plans_jobs where plan_job_id = @plan_job_id and status_id = 100)
			begin
				-- print 'check'
				exec mfr_plan_job_sign;2 @mol_id, @plan_job_id, @task_id, @to_status_id = 100
					-- print 'update'
					update mfr_plans_jobs set status_id = 100 where plan_job_id = @plan_job_id	
					update tasks set status_id = 5 where task_id = @task_id
				-- print 'archive'
				exec mfr_plan_job_sign;4 @mol_id = @mol_id, @plan_job_id = @plan_job_id, @task_id = @task_id
			end
		end

		update mfr_plans_jobs
		set d_closed = case when status_id = 100 then isnull(d_closed, getdate()) else null end
		where plan_job_id = @plan_job_id

	END TRY

	BEGIN CATCH
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH
end
go
-- helper: check job
create proc mfr_plan_job_sign;2
	@mol_id int,
	@plan_job_id int,
	@task_id int = null,
	@to_status_id int = null
as
begin
	if exists(
		select 1 from mfr_plans_jobs_details jd
			join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
		where j.plan_job_id = @plan_job_id 
			and j.type_id <> 5 -- кроме кооперации
			and fact_q > 0
			and not exists(select 1 from mfr_plans_jobs_executors where detail_id = jd.id)
			and not (
				@mol_id = j.add_mol_id
				or dbo.isinrole(@mol_id, 'Admin,Mfr.Moderator') = 1
				)
		)
	begin
		raiserror('Если указано фактическое количество, то должны быть указаны исполнители и фактическое время. Закрытие сменного задания отменено.', 16, 1)
	end

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin,Mfr.Admin')

	if @to_status_id = 100
		-- and @is_admin = 0
		and not exists(
			select 1 from mfr_plans_jobs_details
			where plan_job_id = @plan_job_id and fact_q > 0
		)
	begin
		raiserror('В сменном задании нет строк, в которых указано фактическое количество. Закрытие сменного задания отменено.', 16, 1)
	end

	if @to_status_id = 100
		and @is_admin = 0
		and exists(
			select 1 from mfr_plans_jobs_details jd
				join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
			where j.plan_job_id = @plan_job_id 
				and fact_q <> plan_q
				and fact_q > 0
				and j.executor_id = @mol_id
		)
	begin
		declare @error varchar(max) = '#Ошибка: Фактическое количество не совпадает с планом. Закрытие сменного задания может быть осуществлено через диспетчера.'

		if @task_id is not null
		begin
			declare @hist_id int = (select top 1 hist_id from tasks_hists where task_id = @task_id order by hist_id desc)
			if @hist_id is not null update tasks_hists set body = concat(body, ' ', @error) where hist_id = @hist_id
		end

		raiserror(@error, 16, 1)
	end
end
go
-- helper: auto archive
create proc mfr_plan_job_sign;4
	@mol_id int,
	@plan_job_id int,
	@task_id int
as
begin

	declare @new_job_id int -- новое авто-архивное задание

	BEGIN TRY
	BEGIN TRANSACTION

		if exists(select 1 from mfr_plans_jobs_details where plan_job_id = @plan_job_id and plan_q > isnull(fact_q,0))
			and exists(select 1 from mfr_plans_jobs_details where plan_job_id = @plan_job_id and fact_q > 0)
		begin
			-- print 'slice'
				declare @slice uniqueidentifier = (select slice from mfr_plans_jobs where plan_job_id = @plan_job_id)
				declare @root_id int

				if @slice is null begin
					set @slice = newid()
					set @root_id = @plan_job_id
					update mfr_plans_jobs set slice = @slice where plan_job_id = @plan_job_id
				end

				else begin
					set @root_id = (select min(plan_job_id) from mfr_plans_jobs where slice = @slice)
				end

			-- print 'авто-архив выполненных строк'				
				declare @new_job app_pkids

				insert into mfr_plans_jobs(
					plan_id, place_id, place_to_id,
					d_doc, d_closed, status_id,
					number, note, add_mol_id, executor_id,
					slice
					)
					output inserted.plan_job_id into @new_job
				select
					plan_id, place_id, place_to_id,
					d_doc, isnull(d_closed, dbo.today()),
					100,
					number,
					note, @mol_id, executor_id,
					@slice
				from mfr_plans_jobs
				where plan_job_id = @plan_job_id

                -- @plan_job_id - оставшееся задание
				-- @new_job_id - задание в статусе "Закрыто"
                set @new_job_id = (select top 1 id from @new_job)
				
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				values(dbo.objs_buffer_id(@mol_id), 'mfj', @new_job_id, 0)

			-- print 'auto-number'
				declare @root_number varchar(100) = (select number from mfr_plans_jobs where plan_job_id = @root_id)
				declare @count_childs int = (select count(*) - 1 from mfr_plans_jobs where slice = @slice and status_id >= 0)

				update mfr_plans_jobs set 
					number = concat(@root_number, '/', @count_childs)				
				where plan_job_id = @new_job_id

			-- print 'insert details'
				declare @map_details table(source_detail_id int index ix_source, target_detail_id int)

				insert into mfr_plans_jobs_details(
					reserved, plan_job_id, mfr_doc_id, product_id, content_id, parent_item_id, parent_item_q, item_id, oper_number, oper_name, prev_place_id, oper_id,
					plan_q, fact_q,
					norm_duration, norm_duration_wk, plan_duration_wk, plan_duration_wk_id, duration_wk, duration_wk_id, note, unit_name
					)
					output inserted.reserved, inserted.id into @map_details
				select
					id, @new_job_id, mfr_doc_id, product_id, content_id, parent_item_id, parent_item_q, item_id, oper_number, oper_name, prev_place_id, oper_id,
                    je.plan_q, je.fact_q,
					jd.norm_duration * je.plan_q / nullif(jd.plan_q,0),
                    jd.norm_duration_wk * je.plan_q / nullif(jd.plan_q,0),
					je.plan_duration_wk, je.plan_duration_wk_id,
					je.duration_wk, je.duration_wk_id,
                    note, unit_name
				from mfr_plans_jobs_details jd
                    join (
                        select 
                            jd2.id as detail_id,
                            coalesce(je2.plan_q, je2.fact_q, jd2.fact_q) as plan_q,
                            coalesce(je2.fact_q, jd2.fact_q) as fact_q,
                            coalesce(je2.plan_duration_wk, jd2.plan_duration_wk) as plan_duration_wk,
                            coalesce(je2.plan_duration_wk_id, jd2.plan_duration_wk_id) as plan_duration_wk_id,
                            coalesce(je2.duration_wk, jd2.duration_wk) as duration_wk,
                            coalesce(je2.duration_wk_id, jd2.duration_wk_id) as duration_wk_id
                        from mfr_plans_jobs_details jd2
                            left join (
                                select 
                                    detail_id,
                                    sum(plan_q) as plan_q,
                                    sum(fact_q) as fact_q,
                                    sum(plan_duration_wk) as plan_duration_wk,
                                    max(plan_duration_wk_id) as plan_duration_wk_id,
                                    sum(duration_wk) as duration_wk,
                                    max(duration_wk_id) as duration_wk_id
                                from mfr_plans_jobs_executors
                                where fact_q > 0
                                group by detail_id
                            ) je2 on je2.detail_id = jd2.id
                    ) je on je.detail_id = jd.id
				where jd.plan_job_id = @plan_job_id
                    and je.fact_q > 0;

			-- print 'insert executors'
				insert into mfr_plans_jobs_executors(
					detail_id, status_id, mol_id, d_doc, plan_duration_wk, plan_duration_wk_id, duration_wk, duration_wk_id, plan_q, fact_q, wk_shift, rate_price, note
					)
				select
					map.target_detail_id, x.status_id,
                    mol_id, x.d_doc,
                    plan_duration_wk, plan_duration_wk_id, duration_wk, duration_wk_id, 
                    x.plan_q, x.fact_q, x.wk_shift, x.rate_price,
                    note
				from mfr_plans_jobs_executors x
					join @map_details map on map.source_detail_id = x.detail_id

				-- refine d_closed
				update j set d_closed = e.d_doc
				from mfr_plans_jobs j
					join (
						select jd.plan_job_id, max(je.d_doc) as d_doc
						from mfr_plans_jobs_details jd
							join mfr_plans_jobs_executors je on je.detail_id = jd.id
						group by jd.plan_job_id
					) e on e.plan_job_id = j.plan_job_id
				where j.plan_job_id = @new_job_id
				
				-- delete source executors
				delete x from mfr_plans_jobs_executors x
					join @map_details map on map.source_detail_id = x.detail_id
			
			-- print 'insert equipments'
				insert into mfr_plans_jobs_equipments(
					detail_id, equipment_id, plan_loading, loading, note
					)
				select
					map.target_detail_id, x.equipment_id, x.plan_loading, x.loading, x.note
				from mfr_plans_jobs_equipments x
					join @map_details map on map.source_detail_id = x.detail_id

			-- print 'delete completed'
				delete from mfr_plans_jobs_details
				where plan_job_id = @plan_job_id
					and plan_q <= fact_q

			-- print 'update partial completed'
				update mfr_plans_jobs_details set 
                    plan_q = plan_q - fact_q,
					fact_q = null
				where plan_job_id = @plan_job_id
					and plan_q > fact_q

			-- print 'update statuses'
				update mfr_plans_jobs set status_id = 2 where plan_job_id = @plan_job_id -- исполнение
				update tasks set status_id = 2 where task_id = @task_id -- исполнение

		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH 
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		DECLARE @ERR VARCHAR(MAX); SET @ERR = ERROR_MESSAGE()
		RAISERROR (@ERR, 16, 3)
	END CATCH
end
go
