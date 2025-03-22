if object_id('mfr_opers_buffer_action') is not null drop proc mfr_opers_buffer_action
go
create proc mfr_opers_buffer_action
	@mol_id int,
	@action varchar(32),
	@project_task_id int = null,
    @selected_date date = null,
    @queue_id uniqueidentifier = null
as
begin
    set nocount on;

	declare @today datetime = dbo.today()
    declare @proc_name varchar(100) = object_name(@@procid)

	-- @buffer
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
    declare @buffer as app_pkids
		if @queue_id is null
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfo')
		else
			insert into @buffer select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'mfo'
	
	-- @jobs_details
	declare @jobs_details as app_pkids
		insert into @jobs_details select distinct jd.id
		from v_mfr_plans_jobs_details jd
        	join @buffer i on i.id = jd.oper_id
        where jd.job_status_id between 0 and 99
            and isnull(jd.fact_q, 0) = 0
	
    -- @jobs
	declare @jobs as app_pkids
		insert into @jobs select distinct jd.PLAN_JOB_ID
		from v_mfr_plans_jobs_details jd
            join @jobs_details i on i.id = jd.id

	declare @contents table(content_id int primary key, item_id int, context_id varchar(24))

    BEGIN TRY
    BEGIN TRANSACTION

        if @action in ('CheckAccessAdmin', 'CheckAccess')
        begin
            if (
                select count(distinct sd.subject_id) 
                from sdocs_mfr_opers o
                    join sdocs_mfr_contents c on c.content_id = o.content_id
                        join sdocs sd on sd.doc_id = c.mfr_doc_id
                where o.oper_id in (select id from @buffer)
                ) > 1
            begin
                raiserror('Элементы состава изделия должны быть из одного субъекта учёта.', 16, 1)
            end

            declare @subject_id int = (
                select top 1 sd.subject_id 
                from sdocs_mfr_opers o
                    join sdocs_mfr_contents c on c.content_id = o.content_id
                        join sdocs sd on sd.doc_id = c.mfr_doc_id
                where o.oper_id in (select id from @buffer)
                )
        
            if dbo.isinrole_byobjs(@mol_id, 
                case when @action = 'CheckAccessAdmin' then 'Mfr.Admin' else 'Mfr.Moderator' end,
                'SBJ', @subject_id) = 0
            begin
                raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта.', 16, 1)
            end
        end

        else if @action = 'BindProject' 
        begin
            exec mfr_opers_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

            if @project_task_id is not null
                update x set project_task_id = @project_task_id, project_task_name = left(p.name, 50)
                from sdocs_mfr_opers x
                    join @buffer i on i.id = x.oper_id
                    join projects_tasks t on t.task_id = @project_task_id
                        join projects p on p.project_id = t.project_id
            else            
                update x set project_task_id = null, project_task_name = null
                from sdocs_mfr_opers x
                    join @buffer i on i.id = x.oper_id
        end

		else if @action = 'CloseRows'
		begin
			exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action, @jobs = @jobs

			-- mark as completed
			update x set 
				duration_wk = isnull(duration_wk, plan_duration_wk),
				duration_wk_id = isnull(duration_wk_id, plan_duration_wk_id),
				fact_q = isnull(nullif(fact_q,0), plan_q)
			from mfr_plans_jobs_executors x
				join @buffer i on i.id = x.detail_id

			-- mfr_plans_jobs_details
            update x set
				fact_q = isnull(nullif(fact_q,0), plan_q),
				fact_defect_q = 0,
				update_mol_id = @mol_id, update_date = getdate()
			from mfr_plans_jobs_details x
				join @jobs_details i on i.id = x.id

            -- express update opers
			update x set
                fact_q = x.plan_q
			from sdocs_mfr_opers x
				join @buffer i on i.id = x.oper_id
                join mfr_plans_jobs_details jd on jd.oper_id = x.oper_id and jd.plan_q = x.plan_q
                    join @jobs_details jdi on jdi.id = jd.id
		end

        else if @action = 'CloseJobs'
        begin
            exec mfr_plan_jobs_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action, @jobs = @jobs

            if @queue_id is not null begin
                delete from queues_objs where queue_id = @queue_id and obj_type = 'mfj'
                insert into queues_objs(queue_id, obj_type, obj_id) select @queue_id, 'mfj', id from @jobs
            end
            else begin
                delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfj'
                
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select @buffer_id, 'mfj', id, 0 from @jobs
            end

            -- set d_closed
            update mfr_plans_jobs set 
                d_closed = isnull(@selected_date, @today)
            where plan_job_id in (select id from @jobs)

            -- close jobs
            exec mfr_plan_jobs_buffer_action @mol_id = @mol_id, @action ='BindStatus', @status_id = 100, @queue_id = @queue_id
        end    
    COMMIT TRANSACTION
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        declare @err varchar(max); set @err = error_message()
        raiserror (@err, 16, 3)
    END CATCH -- TRANSACTION
end
go
