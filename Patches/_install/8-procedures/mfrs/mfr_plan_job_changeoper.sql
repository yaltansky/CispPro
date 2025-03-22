if object_id('mfr_plan_job_changeoper') is not null drop proc mfr_plan_job_changeoper
go
create proc mfr_plan_job_changeoper
	@mol_id int,
	@detail_id int,
	@draft_oper_id int
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @subject_id int = (
		select top 1 subject_id
		from mfr_plans_jobs
		where plan_job_id in (select distinct plan_job_id from mfr_plans_jobs_details where id = @detail_id)
		)

	if dbo.isinrole_byobjs(@mol_id, 
		'Mfr.Admin',
		'SBJ', @subject_id) = 0
	begin
		raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта.', 16, 1)
		return
	end

	declare @oper_number int, @oper_name varchar(50)
	select 
		@oper_number = number,
		@oper_name = name
	from mfr_drafts_opers where oper_id = @draft_oper_id

	BEGIN TRY
	
		update jd set oper_number = @oper_number, oper_name = o.name, oper_id = o.oper_id
		from mfr_plans_jobs_details jd
			join (
				select plan_job_id, item_id, oper_number
				from mfr_plans_jobs_details
				where id = @detail_id
			) jj on jj.plan_job_id = jd.plan_job_id and jj.item_id = jd.item_id and jj.oper_number = jd.oper_number
			join sdocs_mfr_opers o on o.content_id = jd.content_id and o.number = @oper_number and o.name = @oper_name

	END TRY

	BEGIN CATCH
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH
end
go
