if object_id('queue_append') is not null drop proc queue_append
go
create proc [queue_append]
	@queue_id uniqueidentifier = null,
	@dbname varchar(32) = null,
	@mol_id int = -25,
	@group_name varchar(100) = 'undefined',
	@thread_id varchar(32) = 'mfrs',
	@name varchar(100),
	@sql_cmd nvarchar(max),
	@priority int = 500,
	@use_rmq bit = 0,
	@use_buffer bit = 1
as
begin
	set nocount on;

	if @queue_id is null set @queue_id = newid()
	if @dbname is null set @dbname = db_name()

	declare @uid int

	if @group_name in ('broker-agent', 'broker-agent-low', 'queue-agent')
		-- for these groups we support only one message by @dbname
		select top 1 @uid = id from queues with(nolock) where dbname = @dbname and group_name = @group_name

	if @uid is null
	begin
		insert into queues(dbname, thread_id, priority_id, group_name, queue_id, mol_id, name, sql_cmd, use_rmq)
		values(@dbname, @thread_id, @priority, @group_name, @queue_id, @mol_id, @name, @sql_cmd, @use_rmq)

		if @use_buffer = 1
			and @group_name not in ('broker-agent', 'broker-agent-low', 'queue-agent')
		begin
			insert into queues_objs(queue_id, obj_type, obj_id)
			select @queue_id, obj_type, obj_id
			from objs_folders_details
			where folder_id = dbo.objs_buffer_id(@mol_id)
		end
	end
	else
		update queues set queue_id = @queue_id, process_start = null, process_end = null where id = @uid
end
GO
