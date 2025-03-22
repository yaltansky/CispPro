if object_id('mfr_wk_sheet_sign') is not null drop proc mfr_wk_sheet_sign
go
create proc mfr_wk_sheet_sign
	@mol_id int,
	@task_id int,
	@action_id varchar(32)
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @type_id int, @status_id int, @author_id int
	declare @refkey varchar(250)

	select 
		@type_id = type_id,
		@status_id = status_id,
		@refkey = refkey,
		@author_id = author_id
	from tasks where task_id = @task_id

	declare @wk_sheet_id int = dbo.strtoken(@refkey, '/', 4)

	if @action_id in ('Send')
		update mfr_wk_sheets set status_id = 0
		where wk_sheet_id = @wk_sheet_id

	if @action_id in ('Assign')
	begin
		declare @executor_id int = (select top 1 mol_id from tasks_mols where task_id = @task_id and role_id = 1 and mol_id <> @author_id)
		update mfr_wk_sheets set status_id = 1, executor_id = @executor_id
		where wk_sheet_id = @wk_sheet_id
	end
	
	if @action_id in ('Redirect')
	begin
		update mfr_wk_sheets set 
			status_id = 1,
			executor_id = (select analyzer_id from tasks where task_id = @task_id)
		where wk_sheet_id = @wk_sheet_id
	end

	if @action_id in ('AcceptToExecute')
		update mfr_wk_sheets set status_id = 2
		where wk_sheet_id = @wk_sheet_id
		
	if @action_id in ('Revoke') 
	begin
		exec mfr_wk_sheet_sign;2 @mol_id, @wk_sheet_id
		update mfr_wk_sheets set status_id = -2 where wk_sheet_id = @wk_sheet_id	
		update tasks set status_id = 5 where task_id = @task_id
	end

	if @action_id in ('PassToAcceptance', 'Close') 
	begin
		update mfr_wk_sheets set status_id = 100 where wk_sheet_id = @wk_sheet_id	
		update tasks set status_id = 5 where task_id = @task_id
	end

end
go
