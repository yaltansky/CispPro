if object_id('deal_sign') is not null drop proc deal_sign
go
create proc deal_sign
	@task_id int,
	@action_id varchar(32)
as
begin

	set nocount on;	

	declare 
		@type_id int, @status_id int,
		@refkey varchar(250),
		@analyzer_id int
	
	select 
		@type_id = type_id,
		@status_id = status_id,
		@refkey = refkey,
		@analyzer_id = analyzer_id
	from tasks where task_id = @task_id

	declare @deal_id int = try_parse(dbo.strtoken(@refkey, '/', 3) as int)

	if @action_id in ('SendAndClose')
	begin
		declare @folder_id int = try_parse(substring(dbo.strtoken(@refkey, '?', 2), 11, 50) as int)

		update x
		set admin_id = @analyzer_id
		from projects x
			join objs_folders_details fd on fd.folder_id = @folder_id and fd.obj_type = 'dl' and fd.obj_id = x.project_id

		update x
		set status_id = 21
		from deals x
			join objs_folders_details fd on fd.folder_id = @folder_id and fd.obj_type = 'dl' and fd.obj_id = x.deal_id
	end

	else if @action_id in ('Assign')
		update deals set status_id = 22 where deal_id = @deal_id
	
	else if @action_id in ('Refine')
		update deals set status_id = 20 where deal_id = @deal_id

	else if @action_id in ('PassToAcceptance') begin
		update deals set status_id = 23 where deal_id = @deal_id
		update tasks set status_id = 5 where task_id = @task_id
	end

	else if @action_id = 'RouteReject' and @status_id = 5
		update deals set status_id = 20 where deal_id = @deal_id
	
	else if @action_id in ('RouteSign', 'RouteRequirements') and @status_id = 5
		update deals set status_id = 23 where deal_id = @deal_id
	
end
go
