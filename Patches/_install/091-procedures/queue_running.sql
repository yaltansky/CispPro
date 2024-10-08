if object_id('queue_running') is not null drop proc queue_running
go
-- exec queue_running 'mfrs', 1000
create proc [queue_running]
	@thread_id varchar(32),
	@user_id int,
	@items varchar(max) = null
as
begin

	declare @ids as app_pkids
	
	if @items is not null
		insert into @ids select distinct item
		from dbo.str2rows(@items, ',')

	select
		Q.ID,
		Q.PARENT_ID,
		Q.DBNAME,
		Q.NAME,
		MOL_NAME = MOLS.NAME,
		Q.ADD_DATE,
		Q.PROCESS_START,
		Q.PROCESS_END,
		Q.PROCESS_DURATION,
		Q.ERRORS		
	from queues q with(nolock)
		join mols on mols.MOL_ID = q.MOL_ID
	where thread_id = @thread_id
		and dbname = db_name()
		and group_name not like '%broker%'
		and (
			process_end is null
			or id in (select id from @ids)
			or (q.errors is not null and q.mol_id = @user_id)
		 )
	order by 
		q.priority_id,
		isnull(q.parent_id, q.id),
		case when q.parent_id is null then 0 else 1 end,
		q.id

end
GO
