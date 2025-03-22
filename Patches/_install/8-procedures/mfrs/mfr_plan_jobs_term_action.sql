if object_id('mfr_plan_jobs_term_action') is not null drop proc mfr_plan_jobs_term_action
go
-- exec mfr_plan_jobs_term_action 1000
create proc mfr_plan_jobs_term_action
	@mol_id int,	
	@term_id int,
	@action varchar(50)
as
begin

	set nocount on;

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	-- @jobsids
		declare @jobsids app_pkids
		insert into @jobsids
		select distinct job_id from mfr_plans_jobs_terms_details
		where term_id = @term_id

	-- check
		declare @subject_id int = (
			select top 1 subject_id
			from mfr_plans_jobs				
			where plan_job_id in (select id from @jobsids)
			)

		if dbo.isinrole_byobjs(@mol_id, 'Mfr.Admin,Mfr.Moderator', 'SBJ', @subject_id) = 0
		begin
			raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта.', 16, 1)
			return
		end

	if @action = 'Close'
	begin		
		-- buffer
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mco'

			insert objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'mco', job_detail_id, 0
			from mfr_plans_jobs_terms_details
			where term_id = @term_id

		-- close
			exec mfr_plan_qjobs_buffer_action
				@mol_id = @mol_id, 
				@action = 'CloseRows'
	end

	else if @action = 'UndoClosed'
	begin
		-- mfr_plans_jobs_details
		update x set fact_q = null
		from mfr_plans_jobs_details x
			join mfr_plans_jobs_terms_details td on td.job_detail_id = x.id
		where td.term_id = @term_id

		-- auto-close
		update x set status_id = 2, update_mol_id = @mol_id, update_date = getdate()
		from mfr_plans_jobs x
		where x.plan_job_id in (select id from @jobsids)
	end
end
go
