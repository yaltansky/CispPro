if object_id('findocs#_sync_push') is not null drop proc findocs#_sync_push
go
create proc findocs#_sync_push
	@ids app_pkids readonly
as
begin
	
	set nocount on;

	insert into findocs#todo select id from @ids

	declare @param varchar(10) = 'dummy'
	declare @h uniqueidentifier

	begin dialog @h
		from service Findocs#SyncService
		to service N'Findocs#SyncService'
        on contract Findocs#SyncContract
        with encryption = off;
	send on conversation @h
		message type Findocs#SyncRequestMessage(@param);
end
go

if object_id('findocs#_sync') is not null drop proc findocs#_sync
go
create proc findocs#_sync
as
begin

	set nocount on;

	declare @param varchar(max)
	declare @h uniqueidentifier
	
	waitfor (
		receive @param = message_body, @h = conversation_handle from Findocs#SyncQueue
	);

	begin try

		if @param is not null
		begin
			declare @ids app_pkids; insert into @ids select distinct findoc_id from findocs#todo
			declare @rowIds app_pkids; insert into @rowIds select distinct row_id from findocs#todo
				
			delete from findocs# where findoc_id in (select id from @ids)

			insert into findocs#(
				findoc_id, detail_id, subject_id, account_id, d_doc, agent_id, goal_account_id, budget_id, article_id, value_ccy, value_rur, fixed_details,
				d_replicated
				)
			select 
				f.findoc_id,
				isnull(fd.id,0),
				f.subject_id,
				f.account_id,
				f.d_doc,
				f.agent_id,
				coalesce(fd.goal_account_id, f.goal_account_id, 0),
				coalesce(fd.budget_id, f.budget_id, 0),
				coalesce(fd.article_id, f.article_id, 0),
				isnull(fd.value_ccy, f.value_ccy),
				isnull(fd.value_rur, f.value_rur),
				f.fixed_details,
				getdate()
			from findocs f
				join @ids i on i.id = f.findoc_id
				left join findocs_details fd on fd.findoc_id = f.findoc_id

			delete from findocs#todo where row_id in (select id from @rowids)
		end
	end try
	
	begin catch
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	end catch

	end conversation @h
end
go

if exists(select 1 from sys.services where name = 'Findocs#SyncService')
	drop service Findocs#SyncService
GO

IF EXISTS(select 1 from sys.service_queues where name = 'Findocs#SyncQueue')
	drop queue Findocs#SyncQueue
GO

IF EXISTS(select 1 from sys.service_contracts where name = 'Findocs#SyncContract')
	drop contract Findocs#SyncContract
GO

IF EXISTS(select 1 from sys.service_message_types where name = 'Findocs#SyncRequestMessage')
	drop message type Findocs#SyncRequestMessage
go

CREATE MESSAGE TYPE Findocs#SyncRequestMessage
GO

CREATE CONTRACT Findocs#SyncContract (
	Findocs#SyncRequestMessage SENT BY INITIATOR
	);
GO

CREATE QUEUE Findocs#SyncQueue
   WITH 
   STATUS = ON,
   RETENTION = OFF ,
   ACTIVATION (
		STATUS = ON,
		PROCEDURE_NAME = findocs#_sync,
		MAX_QUEUE_READERS = 1, 
		EXECUTE AS SELF) 
   ON [DEFAULT];

CREATE SERVICE Findocs#SyncService ON QUEUE Findocs#SyncQueue(Findocs#SyncContract)
GO
