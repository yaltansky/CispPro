if object_id('project_resources_overlimits') is not null drop proc project_resources_overlimits
go

create proc project_resources_overlimits
	@tree_id int,
	@resource_id int,
	@task_id int = null,
	@d_doc datetime = null
as
begin

	set nocount on;

	declare @date_from datetime, @date_to datetime

	if @task_id is not null
	begin
		select @date_from = d_from, @date_to = d_to
		from projects_tasks
		where task_id = @task_id
	end

	select 
		l.D_DOC,
		l.QUANTITY as OUTPUT_Q,
		l.LIMIT_Q,
		l.OVERLIMIT_Q
	from projects_resources_az_limits l
	where tree_id = @tree_id
		and resource_id = @resource_id
		and (@task_id is null or l.d_doc between @date_from and @date_to)
		and l.d_doc >= dbo.today()
		and (@d_doc is null or (l.d_doc >= @d_doc and l.overlimit_q > 0))
	order by l.d_doc

end
go
