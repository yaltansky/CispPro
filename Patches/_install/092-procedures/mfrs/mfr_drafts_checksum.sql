if object_id('mfr_drafts_checksum') is not null drop proc mfr_drafts_checksum
go
create proc [mfr_drafts_checksum]
-- #drafts, #drfats_items
	@draft_id int = null
as
begin

	set nocount on;

	if @draft_id is not null
	begin
		select * into #drafts from sdocs_mfr_drafts where draft_id = @draft_id
			;create index ix_drafts on #drafts(draft_id)
		select * into #drafts_items from sdocs_mfr_drafts_items where draft_id = @draft_id
			;create index ix_drafts on #drafts_items(draft_id, item_id)
	end

	update x
	set chksum = checksum(
			concat(
				'd', x.mfr_doc_id,
				'p', x.product_id,
				'i', x.item_id,
				'buy', x.is_buy,
				'dt', xx.chk_string,
				'st', x.status_id
				)
			)
	from #drafts x
		left join (
			select 
				draft_id,
				concat(
					'i', sum(cast(item_id as float)),
					'tp', sum(cast(item_type_id as float)),
					'buy', sum(cast(is_buy as float)),
					'qn', sum(cast(q_netto as float)),
					'qb', sum(cast(q_brutto as float)),
					'del', sum(cast(item_id * is_deleted as float)),
					'c', count(*)
					) as chk_string
			from #drafts_items
			group by draft_id
		) xx on xx.draft_id = x.draft_id

	if @draft_id is not null
	begin
		update x set chksum = d.chksum
		from sdocs_mfr_drafts x
			join #drafts d on d.draft_id = x.draft_id

		drop table #drafts, #drafts_items
	end
end
GO
