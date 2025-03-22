if object_id('product_sign') is not null drop proc product_sign
go
create proc product_sign
	@mol_id int,
	@task_id int,
	@action_id varchar(32)
as
begin

	set nocount on;	

	declare @status_id int
	declare @refkey varchar(250)

	select 		
		@status_id = status_id,
		@refkey = refkey		
	from tasks where task_id = @task_id

	declare @product_id int = dbo.strtoken(@refkey, '/', 4)

	if @action_id in ('Send', 'Assign')
		update products set status_id = 1 where product_id = @product_id

	else if @action_id in ('Refine', 'RouteRequirements')
	begin
		update products set status_id = 0 where product_id = @product_id
		update tasks set status_id = 1 where task_id = @task_id
	end
		
	else if @action_id in ('PassToAcceptance', 'RouteSign', 'Close')
	begin
		update products set status_id = 5 where product_id = @product_id
		update tasks set status_id = 5 where task_id = @task_id
	end
end
go
