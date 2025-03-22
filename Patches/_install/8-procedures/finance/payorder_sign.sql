if object_id('payorder_sign') is not null drop proc payorder_sign
go
create proc payorder_sign
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

	declare @payorder_id int = dbo.strtoken(@refkey, '/', 4)

	select @action_id

	if @action_id in ('Send')
		update payorders
		set status_id = 1
		where payorder_id = @payorder_id
			and status_id = 0
	
	else if @action_id in ('Assign')
		update payorders set status_id = 2 where payorder_id = @payorder_id
		
	else if @action_id in ('Refine')
		update payorders set status_id = 0 where payorder_id = @payorder_id

	else if @action_id in ('PassToAcceptance') begin
		update payorders set status_id = 3 where payorder_id = @payorder_id
		update tasks set status_id = 5 where task_id = @task_id
	end

	else if @action_id = 'RouteReject' and @status_id = 5
		update payorders set status_id = 1 where payorder_id = @payorder_id
	
	else if @action_id in ('RouteSign', 'RouteRequirements') and @status_id = 5
		update payorders set status_id = 3 where payorder_id = @payorder_id
	
end
go
