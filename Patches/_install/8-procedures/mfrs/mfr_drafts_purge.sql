if object_id('mfr_drafts_purge') is not null drop proc mfr_drafts_purge
go
create proc mfr_drafts_purge
	@mol_id int,
	@docs app_pkids readonly
as
begin

	set nocount on;

	create table #purge_drafts(id int primary key)
		insert into #purge_drafts select draft_id
		from mfr_drafts
		where mfr_doc_id in (select id from @docs)

	delete from mfr_drafts where draft_id in (select id from #purge_drafts)
		and isnull(is_deleted,0) = 1

	delete from mfr_drafts_items where draft_id in (select id from #purge_drafts)
		and isnull(is_deleted,0) = 1

	delete from mfr_drafts_opers where draft_id in (select id from #purge_drafts)
		and isnull(is_deleted,0) = 1

    delete x from mfr_drafts x where mfr_doc_id in (select id from @docs) and is_deleted = 1
	delete x from mfr_drafts_items x where not exists(select 1 from mfr_drafts where draft_id = x.draft_id)
	delete x from mfr_drafts_opers x where not exists(select 1 from mfr_drafts where draft_id = x.draft_id)
	delete x from mfr_drafts_opers_executors x where not exists(select 1 from mfr_drafts_opers where oper_id = x.oper_id)
	delete x from mfr_drafts_opers_resources x where not exists(select 1 from mfr_drafts_opers where oper_id = x.oper_id)
	delete x from mfr_drafts_attrs x where not exists(select 1 from mfr_drafts where draft_id = x.draft_id)

end
GO
