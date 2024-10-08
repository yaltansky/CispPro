if object_id('findocs#_sync') is not null drop proc findocs#_sync
go
create proc [findocs#_sync]
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
GO
