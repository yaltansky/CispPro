if object_id('mfr_plan_qjobs_calc_queue') is not null drop proc mfr_plan_qjobs_calc_queue
go
create proc mfr_plan_qjobs_calc_queue
	@details as app_pkids readonly
as
begin

    set nocount on;

	declare @dbname varchar(32) = db_name()
	declare @group_name varchar(30) = 'jobs-queue-agent'

	-- get named queue (if any)
	declare @queue_id uniqueidentifier = (
		select top 1 queue_id from queues
		where dbname = @dbname and group_name = @group_name
			and process_start is null
		)

	if @queue_id is null
	begin
		-- create new queue
		set @queue_id = newid()
		declare @sql_cmd nvarchar(max) = concat('exec mfr_plan_qjobs_calc @queue_id = ''', @queue_id, '''')
		-- push
		exec queue_append @queue_id = @queue_id, @thread_id = 'mfrs',
			@group_name = @group_name,
			@name = 'Агент очереди сменных заданий',
			@priority = 0,
			@sql_cmd = @sql_cmd,
			@use_buffer = 0
		-- push objs
		insert into queues_objs(queue_id, obj_type, obj_id) select @queue_id, 'mco', id from @details
	end
	
	else begin
		-- lock queue
		update queues set process_start = getdate() where queue_id = @queue_id
		-- push objs
		insert into queues_objs(queue_id, obj_type, obj_id) select @queue_id, 'mco', id from @details x
		where not exists(select 1 from queues_objs where queue_id = @queue_id and obj_id = x.id)
		-- unlock queue
		update queues set process_start = null where queue_id = @queue_id
	end

end
go
