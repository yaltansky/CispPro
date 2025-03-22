if object_id('mfr_docs_trf_buffer_action') is not null drop proc mfr_docs_trf_buffer_action
go
create proc mfr_docs_trf_buffer_action
	@mol_id int,
	@action varchar(32),
	@status_id int = null,
	@status_mol_id int = null
as
begin

    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @today datetime = dbo.today()
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'MFTRF')
	
	declare @is_admin bit = dbo.isinrole(@mol_id, 
		isnull(
			dbo.app_registry_varchar(concat(@proc_name, ':view_admin')),
			'Mfr.Admin'
			)
		)

	BEGIN TRY
	BEGIN TRANSACTION

		if @action in ('CheckAccessAdmin', 'CheckAccess')
		begin
			declare @subjects as app_pkids
				insert into @subjects
				select distinct subject_id from sdocs where doc_id in (select id from @buffer)

			if (select count(*) from @subjects) > 1
				raiserror('Документы должны быть из одного субъекта учёта.', 16, 1)

			declare @subject_id int = (select top 1 id from @subjects)
		
			set @action = case when @action = 'CheckAccessAdmin' then 'admin' else 'any' end
			exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = @action, @subject_id = @subject_id
		end

		else if @action = 'Send'
		begin
			exec mfr_docs_trf_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

			update x set status_id = 2
			from sdocs x
				join @buffer i on i.id = x.doc_id
			where (
				@is_admin = 1
				or @mol_id in (x.add_mol_id, x.update_mol_id, x.mol_id) 
				)
				and x.status_id = 0			
		end

		else if @action = 'Commit'
		begin
			exec mfr_docs_trf_buffer_action @mol_id = @mol_id, @action = 'CheckAccessAdmin'

			update x set status_id = 100
			from sdocs x
				join @buffer i on i.id = x.doc_id
		end

		else if @action = 'BindStatus'
		begin
			if @status_id = -1
				exec mfr_docs_trf_buffer_action @mol_id = @mol_id, @action = 'CheckAccessAdmin'
			else
				exec mfr_docs_trf_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

			if @is_admin = 0
				and exists(
				select 1 from sdocs
					join @buffer i on i.id = sdocs.doc_id
				where mol_id != @mol_id
				)
			begin
				raiserror('Есть документы, в которых Вы не являетесь автором. Поэтому с этими документами нельзя выполнить данное действие.', 16, 1)
			end

			update x set 
				status_id = @status_id,
				update_mol_id = @mol_id, update_date = getdate()
			from sdocs x
				join @buffer i on i.id = x.doc_id

			if @status_id = 2 -- Отправлено
				update x set executor_id = @status_mol_id
				from sdocs x
					join @buffer i on i.id = x.doc_id
			
			else if @status_id = 10 -- Исполнение
				update x set mol_to_id = @status_mol_id
				from sdocs x
					join @buffer i on i.id = x.doc_id
		end

		else if @action = 'CreateJobs'
		begin
			exec mfr_docs_trf_buffer_action @mol_id = @mol_id, @action = 'CheckAccessAdmin'

			if exists(
				select 1 from sdocs sd
					join @buffer i on i.id = sd.doc_id
				where sd.refkey is not null
				)
			begin
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mftrf'
				
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'MFTRF', id, @mol_id
				from sdocs sd
					join @buffer i on i.id = sd.doc_id
				where sd.refkey is null

				COMMIT TRANSACTION -- to save changes in buffer

				raiserror('Среди выбранных накладных есть документы, по которым ранее были созданы сменные задания. В буфере оставлены только "хорошие" накладные.', 16, 1)
			end

			declare @map table(plan_job_id int primary key, doc_id int)
			declare @plan_id int = (select min(plan_id) from mfr_plans where status_id = 1)

			declare @jobs_details table(
				doc_id int,
				d_doc date,
				place_id int, place_to_id int,
				item_id int,
				oper_number int, oper_name varchar(100),
				q float,
				duration_wk float, duration_wk_id int,
				index ix_doc (doc_id, item_id)
				)

				insert into @jobs_details(doc_id, d_doc, place_id, place_to_id, item_id, q)
				select sp.doc_id, sd.d_doc, sd.place_id, sd.place_to_id, sp.product_id, sp.quantity
				from sdocs_products sp
					join sdocs sd on sd.doc_id = sp.doc_id
						join @buffer i on i.id = sd.doc_id

			-- bind oper_number
				declare @drafts table(
					item_id int, place_id int, draft_id int, oper_number int, oper_name varchar(150),
					index ix_draft(draft_id, place_id),
					index ix_oper(item_id, place_id)					
					)

				insert into @drafts(item_id, place_id, draft_id)
				select j.item_id, j.place_id, max(o.draft_id)
				from mfr_drafts_opers o
					join mfr_drafts d on d.draft_id = o.draft_id
					join (
						select distinct item_id, place_id
						from @jobs_details
					) j on j.item_id = d.item_id and j.place_id = o.place_id
				group by j.item_id, j.place_id

				update x set oper_number = o.number, oper_name = o.name
				from @drafts x
					join mfr_drafts_opers o on o.draft_id = x.draft_id and o.place_id = x.place_id

				update x set oper_number = isnull(o.oper_number, 1), oper_name = isnull(o.oper_name, '#undefined')
				from @jobs_details x
					left join @drafts o on o.item_id = x.item_id and o.place_id = x.place_id

				-- if exists(select 1 from @jobs_details where oper_number is null)
				-- begin
				-- 	delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mftrf'
					
				-- 	insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				-- 	select distinct @buffer_id, 'MFTRF', doc_id, @mol_id
				-- 	from @jobs_details x
				-- 	where oper_number is not null
				-- 		and not exists(
				-- 			select 1 from @jobs_details where oper_number is null
				-- 				and doc_id = x.doc_id
				-- 			)

				-- 	COMMIT TRANSACTION -- to save changes in buffer

				-- 	declare @jobs_details_err int = (select count(*) from @jobs_details where oper_number is null)
				-- 	raiserror('Не для всех участков и деталей удалось сопоставить маршруты. Кол-во несоответствий: %d. В буфере оставлены только "хорошие" накладные.', 16, 1, @jobs_details_err)
				-- end				

			-- create jobs
				insert into mfr_plans_jobs(
					extern_id, type_id, plan_id, subject_id, place_id, place_to_id,
					d_doc, d_closed, number,
					status_id, add_mol_id, note
					)
					output inserted.plan_job_id, inserted.extern_id into @map
				select
					sd.doc_id, 1, @plan_id, sd.subject_id, place_id, place_to_id,
					d_doc, d_doc, concat(sbj.short_name, '/ДСЕ#', sd.doc_id),
					100,
					@mol_id, '<ДСЕ>'
				from sdocs sd			
					join subjects sbj on sbj.subject_id = sd.subject_id
				where sd.doc_id in (select distinct doc_id from @jobs_details)

			-- create jobs details
				insert into mfr_plans_jobs_details(
					plan_job_id, item_id, oper_number, oper_name, plan_q, fact_q, duration_wk, duration_wk_id
					)
				select 
					m.plan_job_id, x.item_id,
					x.oper_number, x.oper_name,
					x.q,
					x.q,
					0, -- duration_wk
					2 -- duration_wk_id (часы)
				from @jobs_details x
					join @map m on m.doc_id = x.doc_id

			-- sync buffer
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfj'
				
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select distinct @buffer_id, 'mfj', plan_job_id, @mol_id
				from @map

			-- back ref
				update x set
					refkey = concat('/mfrs/jobs/', m.plan_job_id),
					status_id = 100
				from sdocs x
					join @map m on m.doc_id = x.doc_id
		end

        else if @action = 'ReadPrices'
        begin
			exec mfr_docs_trf_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'
            exec mfr_docs_trf_readprices @mol_id = @mol_id, @docs = @buffer, @enforce = 1
        end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

    -- trace end
        exec tracer_close @tid
end
go
