if object_id('document_sign') is not null drop proc document_sign
go
create proc document_sign
	@task_id int,
	@action_id varchar(32)
as
begin

	set nocount on;	

	declare @type_id int, @status_id int
	declare @refkey varchar(250)

	select 
		@type_id = type_id,
		@status_id = status_id,
		@refkey = refkey
	from tasks where task_id = @task_id

	declare @document_id int = dbo.strtoken(@refkey, '/', 3)

	if @action_id in ('Send')
		update documents set status_id = 1 where document_id = @document_id
	
	else if @action_id in ('Refine')
		update documents set status_id = 0 where document_id = @document_id

	else if @action_id in ('Close') begin
		update documents set status_id = case when @type_id = 1 then 10 else 0 end
			where document_id = @document_id
		update tasks set status_id = 5 where task_id = @task_id
	end

	else if @action_id in ('Assign') and @type_id = 2
		update documents set last_agree_id = @task_id where document_id = @document_id
	
	else if @action_id = 'RouteReject' and @status_id = 5
		update documents set status_id = 1 where document_id = @document_id
	
	else if @action_id in ('RouteSign', 'RouteRequirements') and @status_id = 5
	begin
		update documents set status_id = 3 where document_id = @document_id
		if @type_id = 1 -- если тип задачи не Лист согласования, то возвращаем задачу в рабочее состояние
			update tasks set status_id = 2 where task_id = @task_id
	end
	
	if @status_id = 5 and @type_id = 2
		update documents set last_agree_id = null where document_id = @document_id

	exec documents_calc_access @document_id = @document_id

end
go
