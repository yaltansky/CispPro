if object_id('mfr_drafts_check') is not null drop proc mfr_drafts_check
go
/*
	declare @drafts app_pkids; insert into @drafts select top 10 draft_id from sdocs_mfr_drafts
	exec mfr_drafts_check @drafts
*/
create proc [mfr_drafts_check]
	@drafts app_pkids readonly
as
begin

	set nocount on;

BEGIN TRY
BEGIN TRANSACTION

	declare @docs as app_pkids
	insert into @docs select distinct mfr_doc_id from sdocs_mfr_drafts where draft_id in (select id from @drafts)
		and mfr_doc_id > 0

	declare @opers table(
		draft_id int,
		oper_id int primary key,
		number int,
		predecessors varchar(50),
		is_first bit,
		is_last bit,
		index ix_number (draft_id, number)
		)

	insert into @opers(draft_id, oper_id, number, predecessors)
		select d.draft_id, x.oper_id, x.number, x.predecessors
		from sdocs_mfr_drafts_opers x
			join sdocs_mfr_drafts d on d.draft_id = x.draft_id
		where d.mfr_doc_id in (select id from @docs)
			and d.is_buy = 0 -- только детали

	declare @predecessors varchar(100), @is_first bit
	update x
	set @predecessors = replace(replace(x.predecessors, ' ', ';'), ',', ';'),
		@is_first = case when l.prev_id is null or isnull(@predecessors,'') = '' then 1 end,
		is_first = @is_first,
		is_last = case when l.next_id is null then 1 end
	from @opers x
		join (
			select 
				oper_id,
				prev_id = lag(oper_id, 1, null) over (partition by draft_id order by number),
				next_id = lead(oper_id, 1, null) over (partition by draft_id order by number)
			from @opers
		) l on l.oper_id = x.oper_id

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH -- TRANSACTION

end
GO
