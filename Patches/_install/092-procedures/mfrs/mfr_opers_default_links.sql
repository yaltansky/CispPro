if object_id('mfr_opers_default_links') is not null drop proc mfr_opers_default_links
go
/*
	declare @ids app_pkids; insert into @ids select oper_id from sdocs_mfr_opers
	delete from sdocs_mfr_opers_links
	exec mfr_opers_default_links @ids
*/
create proc [mfr_opers_default_links]
	@ids app_pkids readonly
as
begin

	set nocount on;

	-- links
	declare @opers table(oper_id int primary key, content_id int, prev_number varchar(20))
		insert into @opers(oper_id, content_id, prev_number)
		select 
			oper_id,
			content_id,
			lag(number, 1, null) over (partition by mfr_doc_id, content_id order by number)
		from sdocs_mfr_opers x
			join @ids i on i.id = x.oper_id

	-- 1 --> 2 --> 3 ... (последовательные операции)
	update x set 
		predecessors = l.prev_number,
		predecessors_def = l.prev_number
	from sdocs_mfr_opers x		
		join @opers l on l.oper_id = x.oper_id

	declare @contents as app_pkids; insert into @contents select distinct content_id from @opers
	exec mfr_items_calc_links @ids = @contents
end
GO
