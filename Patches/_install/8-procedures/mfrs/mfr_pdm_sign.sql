if object_id('mfr_pdm_sign') is not null drop proc mfr_pdm_sign
go
create proc mfr_pdm_sign
	@mol_id int,
	@task_id int,
	@action_id varchar(32)
as
begin

	set nocount on;	

	declare @type_id int, @status_id int, @author_id int
	declare @refkey varchar(250)

	select 
		@type_id = type_id,
		@status_id = status_id,
		@refkey = refkey,
		@author_id = author_id
	from tasks where task_id = @task_id

	if exists(select 1 from tasks where refkey = @refkey and status_id >= 0 and status_id <> 5 and task_id <> @task_id)
		return -- nothing todo (singleton task)
	
	declare @pdm_id int = dbo.strtoken(@refkey, '/', 4)
	declare @executor_id int = (select top 1 mol_id from tasks_mols where task_id = @task_id and role_id = 1)

	if @action_id in ('Send', 'Assign', 'Reject')
		update mfr_pdms set 
			status_id = 2,
			executor_id = @executor_id
		where pdm_id = @pdm_id
	
	else if @action_id in ('PassToAcceptance')
		update mfr_pdms set status_id = 3 where pdm_id = @pdm_id		

	else begin
		
		if @status_id = 0 -- Черновик
			update mfr_pdms set status_id = 0 where pdm_id = @pdm_id

		else if @status_id in (1,2) -- Постановка, Исполнение
			update mfr_pdms set status_id = 2 where pdm_id = @pdm_id

		else if @status_id in (3,4) -- Проверка, Приёмка
			update mfr_pdms set status_id = 3 where pdm_id = @pdm_id

		else if @status_id = 5 -- Завершено
			update mfr_pdms set status_id = 10 where pdm_id = @pdm_id		
	end
end
go
